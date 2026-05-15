import type { FastifyPluginAsync } from 'fastify';

export interface HealthResponse {
  status: 'ok';
  uptime: number;
  timestamp: string;
}

export const healthRoute: FastifyPluginAsync = async (app) => {
  app.get('/health', async (): Promise<HealthResponse> => ({
    status: 'ok',
    uptime: process.uptime(),
    timestamp: new Date().toISOString(),
  }));
};
