import type { FastifyInstance } from 'fastify';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { loadEnv } from '../../src/config/env.js';
import type { HealthResponse } from '../../src/routes/health.js';
import { buildApp } from '../../src/server.js';

describe('GET /health', () => {
  let app: FastifyInstance;

  beforeAll(async () => {
    const env = loadEnv({ NODE_ENV: 'test', LOG_LEVEL: 'fatal' });
    app = await buildApp({ env });
    await app.ready();
  });

  afterAll(async () => {
    await app.close();
  });

  it('returns 200 with status ok and a usable timestamp', async () => {
    const res = await app.inject({ method: 'GET', url: '/health' });

    expect(res.statusCode).toBe(200);
    const body = res.json() as HealthResponse;
    expect(body.status).toBe('ok');
    expect(body.uptime).toBeGreaterThanOrEqual(0);
    expect(Number.isNaN(Date.parse(body.timestamp))).toBe(false);
  });

  it('returns valid JSON content-type', async () => {
    const res = await app.inject({ method: 'GET', url: '/health' });
    expect(res.headers['content-type']).toMatch(/application\/json/);
  });
});
