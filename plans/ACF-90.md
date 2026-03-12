# ACF-90: factory should check token expiry before launching workers

## Summary

Before launching worker containers, `factory` should check whether the Claude OAuth
access token in the env file has expired. If it has, it should re-import fresh
credentials from `~/.claude/.credentials.json` (which the Claude CLI updates
automatically when it refreshes tokens).

The check belongs in `cmd_add`, which is the single code path that all launch
commands (`workers`, `planners`, `add`) flow through.

## Files to Change

| File | Change |
|---|---|
| `factory/factory` | Add `_check_and_refresh_claude_token` helper; call it from `cmd_add` |
| `factory/factory.bats` | Add unit tests for the new token-expiry check |

## Implementation Steps

1. **Add helper `_check_and_refresh_claude_token` in `factory/factory`**

   Place it just before `cmd_add`.

   ```bash
   _check_and_refresh_claude_token() {
       local env_file="$1"
       [[ -z "$env_file" || ! -f "$env_file" ]] && return 0

       local expires_at
       expires_at="$(grep -E "^CLAUDE_TOKEN_EXPIRES_AT=" "$env_file" \
           | cut -d= -f2 | head -1)"
       [[ -z "$expires_at" ]] && return 0   # not using Claude OAuth

       local now_ms
       now_ms="$(date +%s%3N)"   # current time in milliseconds

       if [[ "$expires_at" -le "$now_ms" ]]; then
           echo "Claude token has expired — re-importing credentials..."
           cmd_import_claude_credentials --env-file "$env_file"
       fi
   }
   ```

   Key points:
   - `expiresAt` from `~/.claude/.credentials.json` is milliseconds since epoch.
   - If the key is absent the env file is not using Claude OAuth (e.g., API key
     mode or a non-Claude worker), so the function is a no-op.
   - Delegates the actual re-import to the existing `cmd_import_claude_credentials`
     to avoid duplicating logic.

2. **Call the helper from `cmd_add`**

   Insert the call after `env_file` is resolved and validated, but before
   `_ensure_image` and the container loop:

   ```bash
   # (existing) env_file resolution + validation ...
   local env_file_arg=()
   [[ -n "$env_file" ]] && env_file_arg=(--env-file "$env_file")

   _check_and_refresh_claude_token "$env_file"   # ← new line

   _ensure_image "$image"
   ```

## Testing

Add the following unit tests to `factory/factory.bats`, in a new
`# ── token expiry check ───` section:

1. **No env file → no re-import (no-op)**
   - Call `cmd_add` without `--env-file`; verify `import-claude-credentials`
     is never invoked.

2. **Env file has no `CLAUDE_TOKEN_EXPIRES_AT` → no re-import**
   - Env file contains unrelated vars; verify no re-import.

3. **Token not yet expired → no re-import**
   - Write `CLAUDE_TOKEN_EXPIRES_AT=<far future ms>` to env file; verify no
     re-import.

4. **Token expired → re-imports credentials**
   - Write `CLAUDE_TOKEN_EXPIRES_AT=1` (epoch + 1 ms, definitely expired) and
     a fake `~/.claude/.credentials.json` to a temp HOME; verify
     `import-claude-credentials` is called and the env file is updated with
     fresh tokens.

   Use the `make_creds` helper that already exists in `factory.bats`.

## Risks / Edge Cases

- **`expiresAt` unit**: the value from `~/.claude/.credentials.json` is in
  milliseconds. `date +%s%3N` also returns milliseconds, so the comparison is
  consistent. If Anthropic ever changes the unit the check will break silently
  (tokens would appear perpetually valid). A comment in the code explaining the
  unit assumption is warranted.

- **Credentials file absent during re-import**: `cmd_import_claude_credentials`
  already errors with a clear message if `~/.claude/.credentials.json` is not
  found, so no extra handling needed.

- **No-op for API-key mode**: workers using `ANTHROPIC_API_KEY` (not OAuth) will
  not have `CLAUDE_TOKEN_EXPIRES_AT` in their env file, so the helper exits
  immediately — correct behaviour.

- **Multiple workers**: the token check runs once before the loop that starts N
  containers, which is correct. No need to check per container.

- **Stale token in credentials file**: if `~/.claude/.credentials.json` itself
  contains an expired token (i.e., the CLI has not yet refreshed it), the
  re-import will write an equally expired token. This is an upstream concern;
  the factory's job is only to sync the env file from the credentials file.
