import sensible from '@fastify/sensible';
import websocketPlugin from '@fastify/websocket';
import Fastify, { type FastifyInstance } from 'fastify';

import type { Env } from './config/env.js';
import { createDatabase } from './db/client.js';
import {
  createConvoyGateway,
  type ConvoyGatewayOptions,
} from './realtime/convoy_gateway.js';
import { createConvoyRoutes } from './routes/convoys.js';
import { healthRoute } from './routes/health.js';
import { createPttRoutes } from './routes/ptt.js';
import { createVehicleRoutes } from './routes/vehicles.js';

export interface BuildOptions {
  env: Env;
  gateway?: ConvoyGatewayOptions;
}

export async function buildApp(options: BuildOptions): Promise<FastifyInstance> {
  const app = Fastify({
    logger: {
      level: options.env.LOG_LEVEL,
    },
  });

  await app.register(sensible);
  await app.register(websocketPlugin);
  await app.register(healthRoute);

  const gatewayOptions: ConvoyGatewayOptions = { ...options.gateway };
  if (options.env.REDIS_URL !== undefined) {
    const { RedisFanout } = await import('./realtime/redis_fanout.js');
    const redisFanout = new RedisFanout(options.env.REDIS_URL);
    await redisFanout.connect();
    app.addHook('onClose', async () => {
      await redisFanout.close();
    });
    gatewayOptions.fanout = redisFanout;
  }
  await app.register(createConvoyGateway(gatewayOptions));

  // Routes that need DB stay gated behind DATABASE_URL so tests that
  // don't touch persistence (health, gateway) keep running without one.
  if (options.env.DATABASE_URL !== undefined) {
    const dbHandle = createDatabase({ url: options.env.DATABASE_URL });
    app.addHook('onClose', async () => {
      await dbHandle.sql.end();
    });
    await app.register(createConvoyRoutes({ db: dbHandle }));
    await app.register(createVehicleRoutes({ db: dbHandle }));
    await app.register(createPttRoutes({ db: dbHandle, env: options.env }));
  }

  return app;
}
