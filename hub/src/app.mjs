import express from 'express';
import morgan from 'morgan';
import cors from 'cors';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import tasksRouter from './routes/tasks.mjs';
import statusRouter from './routes/status.mjs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export function createApp() {
  const app = express();
  app.use(cors());
  // custom JSON parser to catch invalid JSON and return 400
  app.use(express.json({ limit: '1mb' }));
  app.use((err, req, res, next) => {
    if (err && err.type === 'entity.parse.failed') {
      return res.status(400).json({ error: 'Invalid JSON', message: 'Request body must be valid JSON' });
    }
    next(err);
  });
  app.use(morgan('dev'));

  // API routes
  app.use('/api/tasks', tasksRouter);
  app.use('/api/status', statusRouter);

  // Serve static UI
  const uiDir = path.join(__dirname, '../ui');
  app.use(express.static(uiDir));

  // 404 fallback for API
  app.use('/api', (req, res) => {
    res.status(404).json({ error: 'Not found' });
  });

  return app;
}

export default createApp;
