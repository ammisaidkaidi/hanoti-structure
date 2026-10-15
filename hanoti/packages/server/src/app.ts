import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import express, { type ErrorRequestHandler } from 'express';
import cors from 'cors';
import helmet from 'helmet';
import { z } from 'zod';
import { greetingRequestSchema, type GreetingResponse, type HealthResponse } from '@app/common';
import { allowedOrigins, dataDirectory } from './config.js';

export function createApp() {
  const app = express();
  app.disable('x-powered-by');
  app.use((_req, res, next) => {
    res.locals.requestId = randomUUID();
    res.setHeader('X-Request-Id', String(res.locals.requestId));
    next();
  });
  app.use(helmet());
  app.use(
    cors({
      origin: (origin, callback) => callback(null, !origin || allowedOrigins.includes(origin)),
    }),
  );
  app.use(express.json({ limit: '32kb' }));

  app.get('/api/health', (_req, res) => {
    const body: HealthResponse = {
      status: 'ok',
      service: 'hanouti-server',
      timestamp: new Date().toISOString(),
    };
    res.json(body);
  });
  app.post('/api/greetings', async (req, res) => {
    const parsed = greetingRequestSchema.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({
        error: 'Validation failed',
        issues: parsed.error.flatten(),
        requestId: res.locals.requestId,
      });
      return;
    }
    // Direct server-only access. data/ is never mounted as a public static directory.
    const asset = JSON.parse(
      await readFile(join(dataDirectory, 'assets/welcome.json'), 'utf8'),
    ) as unknown;
    const { prefix } = z.object({ prefix: z.string() }).parse(asset);
    const body: GreetingResponse = {
      message: `${prefix}, ${parsed.data.name}. Your workspace is ready.`,
    };
    res.json(body);
  });
  app.use((_req, res) => {
    res.status(404).json({ error: 'Not found', requestId: res.locals.requestId });
  });
  const handleError: ErrorRequestHandler = (error: unknown, _req, res, _next) => {
    const status =
      typeof error === 'object' && error !== null && 'status' in error ? error.status : undefined;
    if (status === 400 || status === 413 || status === 415) {
      res.status(status).json({
        error:
          status === 413
            ? 'Request too large'
            : status === 415
              ? 'Unsupported encoding'
              : 'Malformed request',
        requestId: res.locals.requestId,
      });
      return;
    }
    console.error(
      JSON.stringify({
        level: 'error',
        requestId: res.locals.requestId,
        message: error instanceof Error ? error.message : 'Unknown error',
      }),
    );
    res.status(500).json({ error: 'Internal server error', requestId: res.locals.requestId });
  };
  app.use(handleError);
  return app;
}
