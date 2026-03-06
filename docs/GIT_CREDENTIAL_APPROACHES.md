# Git Credential Helper Approaches

This document investigates approaches for authenticating git operations in the AI coding factory workers, with a focus on replacing the current URL-embedding approach. Each approach is evaluated on security, operational simplicity, and fit with this project's containerised architecture.

---

## Context

The `loop` script currently authenticates git operations by injecting credentials directly into the HTTPS URL:

```bash
AUTH_URL="${GIT_REPO_URL/#https:\/\//https://$GIT_USERNAME:$GIT_TOKEN@}"
git clone "$AUTH_URL" "$WORK_DIR"
git -C "$WORK_DIR" remote set-url origin "$AUTH_URL"
```

This is flagged as **M3** in the reliability analysis: `GIT_USERNAME:GIT_TOKEN` appears in the process argument list (`ps aux`) during git operations, visible to any process running as the same user or as root.

---

## Approaches

### 1. URL Embedding (Current)

**How it works:** Credentials are interpolated directly into the remote URL before passing it to `git clone` / `git remote set-url`.

**Security:**
- Token is visible in the process list (`ps aux`) for the duration of git operations.
- Token appears in `git remote -v` output.
- Token may be logged by audit tools, container runtimes, or shells that record commands.
- Token is stored in `.git/config` after `remote set-url`, readable by any process with file access.

**Operational complexity:** Minimal — no additional tooling or setup required.

**Fit:** Works, but leaks credentials in several channels. Acceptable for a proof-of-concept but not for production.

**Verdict:** Replace.

---

### 2. `git credential-store`

**How it works:** Git's built-in plaintext credential store. Credentials are written to `~/.git-credentials` (or a path specified by `--file`). On first use, git calls the helper to retrieve credentials by protocol/host.

```bash
git config --global credential.helper store
# Seed the store once:
git credential approve <<EOF
protocol=https
host=github.com
username=$GIT_USERNAME
password=$GIT_TOKEN
EOF
```

**Security:**
- Credentials no longer appear in the process list or in remote URLs.
- `~/.git-credentials` is plaintext on disk, world-readable if permissions are wrong (git sets it to 0600 by default).
- In a container, the file exists only for the container's lifetime; it is not persisted across restarts unless a volume is mounted.
- If the container image is committed or exported, credentials are baked in.

**Operational complexity:** Low. A one-time `git credential approve` call in the container init script is sufficient.

**Fit:** Good for this project. The container lifetime is ephemeral, so plaintext-on-disk is a minor concern. The main gain is removing credentials from process args and remote URLs.

**Verdict:** Viable improvement over current approach. Best suited when SSH keys are not an option.

---

### 3. `git credential-cache`

**How it works:** Git's in-memory credential store. Credentials are held in a unix-domain socket process, never written to disk. They expire after a configurable timeout (default: 15 minutes).

```bash
git config --global credential.helper 'cache --timeout=3600'
git credential approve <<EOF
protocol=https
host=github.com
username=$GIT_USERNAME
password=$GIT_TOKEN
EOF
```

**Security:**
- No credentials on disk.
- Credentials live in a daemon process owned by the same user, accessible only via a socket in `~/.git/credential/socket`.
- More secure than `credential-store` but credentials are lost on daemon restart or container restart.

**Operational complexity:** Low, but slightly more brittle — if the socket process exits (e.g. killed by OOM), git operations fail until credentials are re-seeded.

**Fit:** Good for containers that process many issues in a single session. Requires re-seeding credentials in the init script and handling socket-not-available errors.

**Verdict:** Slightly more secure than `credential-store` at the cost of extra fragility. Suitable if on-disk credentials are a concern.

---

### 4. Custom Credential Helper Script (`GIT_USERNAME`/`GIT_TOKEN` from environment)

**How it works:** A small script is written as the credential helper. When git needs credentials, it executes the script, which reads from environment variables and prints `username=...` / `password=...` to stdout.

```bash
#!/usr/bin/env bash
# /usr/local/bin/git-credential-env
echo "username=${GIT_USERNAME}"
echo "password=${GIT_TOKEN}"
```

```bash
git config --global credential.helper /usr/local/bin/git-credential-env
```

**Security:**
- Credentials are never on disk.
- Credentials never appear in process args or remote URLs.
- The helper script itself contains no secrets — only references to env vars.
- As long as environment variables are not logged, credentials are not exposed.
- Helper script must not be world-writable (a malicious replacement could exfiltrate tokens).

**Operational complexity:** Low. A small script (already installed in the Docker image) plus a `git config` line in the init script. No seeding step required.

**Fit:** Excellent for this project. Credentials already arrive via environment variables; this approach consumes them in the right place. Works across container restarts as long as env vars are re-injected.

**Verdict:** Recommended approach. Cleanest security posture for a containerised, environment-variable-driven system.

---

### 5. `GIT_ASKPASS`

**How it works:** Git calls the program named in `GIT_ASKPASS` with a text prompt (e.g. `"Username for 'https://github.com': "`) and expects the answer on stdout. A script can pattern-match the prompt to return the right value.

```bash
#!/usr/bin/env bash
# /usr/local/bin/git-askpass
case "$1" in
  *Username*) echo "$GIT_USERNAME" ;;
  *Password*) echo "$GIT_TOKEN"    ;;
esac
```

```bash
export GIT_ASKPASS=/usr/local/bin/git-askpass
```

**Security:**
- Same as custom credential helper (Approach 4): no credentials on disk or in process args.
- More fragile: the prompt text is not part of git's public API and can vary across git versions or remote hosts.

**Operational complexity:** Medium. Prompt matching is fiddly and error-prone.

**Fit:** Functional, but Approach 4 (credential helper) is strictly cleaner for non-interactive use.

**Verdict:** Approach 4 is preferable. Use `GIT_ASKPASS` only if credential helpers are unavailable.

---

### 6. `~/.netrc`

**How it works:** The standard Unix `.netrc` file stores credentials by hostname. `git` (via libcurl) reads it for HTTPS authentication.

```
machine github.com
  login $GIT_USERNAME
  password $GIT_TOKEN
```

**Security:**
- Plaintext on disk (`~/.netrc` should be mode 0600).
- Similar profile to `credential-store` but wider system impact: `~/.netrc` is also read by `curl`, `ftp`, and other tools.
- No credentials in process args.

**Operational complexity:** Low. Template the file in the init script from env vars.

**Fit:** Works, but the wider attack surface (other tools also reading the file) and plaintext-on-disk make this less attractive than Approach 4.

**Verdict:** Acceptable fallback if git credential helpers are somehow unavailable, but inferior to Approach 4.

---

### 7. SSH Keys

**How it works:** Replace the HTTPS remote URL with an SSH remote (`git@github.com:owner/repo.git`). Authentication uses an RSA/Ed25519 key pair; the private key is mounted into the container.

```bash
mkdir -p ~/.ssh
echo "$GIT_SSH_PRIVATE_KEY" > ~/.ssh/id_ed25519
chmod 600 ~/.ssh/id_ed25519
ssh-keyscan github.com >> ~/.ssh/known_hosts
```

`GIT_REPO_URL` would need to be an SSH URL, or `loop` would need to rewrite it.

**Security:**
- No passwords or tokens in env vars, process args, URLs, or files (beyond the key file itself).
- Private key file should be mode 0600, ideally mounted from a Docker secret.
- Key can be scoped to a single repository (deploy keys) or to the account.
- Revocable independently of user credentials.

**Operational complexity:** Higher. Requires:
- Generating and registering an SSH key on the git host.
- Mounting the private key into the container (Docker secret or env var containing the key material).
- Rewriting the remote URL from HTTPS to SSH, or receiving an SSH URL in `GIT_REPO_URL`.
- Managing `known_hosts` to prevent TOFU attacks.

**Fit:** The best security posture for long-running production workers, but the operational overhead of key management is higher than token-based approaches. Most appropriate when workers operate for months/years.

**Verdict:** Best long-term solution. Worth investing in when the system moves to production at scale.

---

### 8. Docker Secrets (mounted credentials file)

**How it works:** Docker Swarm or Kubernetes mounts credentials as files at well-known paths (e.g. `/run/secrets/git_token`). The init script reads the file and seeds the git credential store.

```bash
GIT_TOKEN="$(cat /run/secrets/git_token)"
git credential approve <<EOF
protocol=https
host=github.com
username=$GIT_USERNAME
password=$GIT_TOKEN
EOF
```

**Security:**
- Secret file is in a `tmpfs` mount, not on the container's writable layer.
- Not visible in environment variables (`docker inspect` does not show secret values).
- Stronger isolation than env-var secrets.

**Operational complexity:** High. Requires Docker Swarm mode or Kubernetes; not available with plain `docker run`. The `factory` CLI would need significant changes to support secrets injection.

**Fit:** Not currently compatible with the project's `docker run`-based `factory` CLI. Would require a significant architectural step up.

**Verdict:** Future consideration if the project migrates to Swarm or Kubernetes. Overkill for the current architecture.

---

## Comparison Table

| Approach | Credentials in process args | Credentials on disk | Credentials in env vars | Complexity | Recommended for this project |
|---|---|---|---|---|---|
| 1. URL embedding (current) | Yes | Yes (`.git/config`) | Yes | None | No |
| 2. `credential-store` | No | Yes (`~/.git-credentials`) | No (after seeding) | Low | Acceptable |
| 3. `credential-cache` | No | No | No (after seeding) | Low-Med | Acceptable |
| 4. Custom helper (env vars) | No | No | Yes | Low | **Yes** |
| 5. `GIT_ASKPASS` | No | No | Yes | Medium | Fallback |
| 6. `~/.netrc` | No | Yes | No (after seeding) | Low | Acceptable |
| 7. SSH keys | No | Key file only | Optional | High | Best long-term |
| 8. Docker secrets | No | No | No | Very high | Future |

---

## Recommendation

**Short term:** Replace URL embedding with a **custom credential helper script** (Approach 4).

- Install a small `git-credential-env` script in the worker Docker images.
- Configure `git config --global credential.helper git-credential-env` in the Dockerfile or init script.
- Remove the `AUTH_URL` construction from `loop`.

This eliminates credentials from process args and remote URLs with minimal change to the existing architecture. The `GIT_USERNAME` and `GIT_TOKEN` environment variables continue to be the source of truth, so no changes to how workers are launched are needed.

**Long term:** Migrate to **SSH deploy keys** (Approach 7) once the worker deployment is more stable. SSH deploy keys can be scoped per repository, are independently revocable, and never appear in environment variables.

---

## Implementation Sketch (Approach 4)

Add to `workers/claude/Dockerfile` (and analogous worker Dockerfiles):

```dockerfile
# Install git credential helper that reads from environment variables
COPY git-credential-env /usr/local/bin/git-credential-env
RUN chmod +x /usr/local/bin/git-credential-env && \
    git config --global credential.helper /usr/local/bin/git-credential-env
```

`git-credential-env`:
```bash
#!/usr/bin/env bash
echo "username=${GIT_USERNAME}"
echo "password=${GIT_TOKEN}"
```

In `loop`, replace:
```bash
# Before
AUTH_URL="${GIT_REPO_URL/#https:\/\//https://$GIT_USERNAME:$GIT_TOKEN@}"
git clone "$AUTH_URL" "$WORK_DIR"
git -C "$WORK_DIR" remote set-url origin "$AUTH_URL"
```

```bash
# After
git clone "$GIT_REPO_URL" "$WORK_DIR"
# (No remote set-url needed — the helper is called automatically)
```
