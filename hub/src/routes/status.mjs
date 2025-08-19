import express from 'express';

const router = express.Router();

router.get('/', (req, res) => {
  res.json({
    status: 'ok',
    service: 'AI Coding Factory Hub',
    version: '0.1.0',
    timestamp: new Date().toISOString(),
    endpoints: [
      '/api/status.cgi - Service status',
      '/api/tasks.cgi - Tasks CRUD'
    ],
  });
});

export default router;
