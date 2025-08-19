import { createApp } from './app.mjs';

const app = createApp();
const PORT = process.env.HUB_PORT || 8080;
const HOST = process.env.HUB_HOST || '0.0.0.0';

app.listen(PORT, HOST, () => {
  console.log(`Hub listening on http://${HOST}:${PORT}`);
});
