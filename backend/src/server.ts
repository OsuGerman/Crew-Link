import cors from '@fastify/cors';
import sensible from '@fastify/sensible';
import websocketPlugin from '@fastify/websocket';
import Fastify, { type FastifyInstance } from 'fastify';

import type { Env } from './config/env.js';
import { createDatabase, type DatabaseHandle } from './db/client.js';
import {
  createConvoyGateway,
  type ConvoyGatewayOptions,
} from './realtime/convoy_gateway.js';
import { createDbPositionStore } from './realtime/position_store.js';
import { createInMemorySnapshotStore } from './realtime/snapshot_store.js';
import { createConvoyRoutes } from './routes/convoys.js';
import { healthRoute } from './routes/health.js';
import { createPttRoutes } from './routes/ptt.js';
import { createVehicleRoutes } from './routes/vehicles.js';
import {
  createAuthHook,
  createFirebaseTokenVerifier,
  createLeaderResolver,
  createMemberResolver,
  devTokenVerifier,
  type TokenVerifier,
} from './services/auth.js';

export interface BuildOptions {
  env: Env;
  gateway?: ConvoyGatewayOptions;
  // Override the token verifier (tests inject a fake). Defaults to real
  // Firebase verification when FIREBASE_PROJECT_ID is set, else the dev
  // verifier (token IS the user id).
  verifyToken?: TokenVerifier;
}

export async function buildApp(options: BuildOptions): Promise<FastifyInstance> {
  const app = Fastify({
    logger: {
      level: options.env.LOG_LEVEL,
    },
  });

  await app.register(sensible);
  // Allow the Flutter web build (Chrome) to call the API cross-origin. The API
  // is token-gated (Bearer, no cookies), so reflecting the request origin is
  // safe. Set CORS_ORIGIN (comma-separated) to lock down to known hosts.
  await app.register(cors, {
    origin: options.env.CORS_ORIGIN
      ? options.env.CORS_ORIGIN.split(',').map((o) => o.trim())
      : true,
  });
  await app.register(websocketPlugin);
  await app.register(healthRoute);

  // Never leak internal errors/stack traces to clients. Typed HTTP errors
  // (sensible, validation) keep their status + message; anything else becomes a
  // generic 500 and is logged server-side.
  app.setErrorHandler((error, request, reply) => {
    const err = error as Error & { statusCode?: number };
    const statusCode = err.statusCode ?? 500;
    if (statusCode >= 500) {
      request.log.error({ err }, 'unhandled error');
      return reply.code(statusCode).send({ error: 'internal server error' });
    }
    return reply
      .code(statusCode)
      .send({ error: err.name, message: err.message });
  });

  // Refuse to start in production with the insecure dev verifier (which would
  // accept ANY bearer token as a valid identity). Dev/test may still use it.
  if (
    options.verifyToken === undefined &&
    options.env.FIREBASE_PROJECT_ID === undefined &&
    options.env.NODE_ENV === 'production'
  ) {
    throw new Error(
      'FIREBASE_PROJECT_ID must be set in production — refusing to start with ' +
        'the insecure dev token verifier.',
    );
  }
  const verifyToken: TokenVerifier =
    options.verifyToken ??
    (options.env.FIREBASE_PROJECT_ID !== undefined
      ? createFirebaseTokenVerifier(options.env.FIREBASE_PROJECT_ID)
      : devTokenVerifier);

  // The prod fail-fast above only fires for NODE_ENV='production'. A hosted
  // server with NODE_ENV unset (defaults to 'development') and no
  // FIREBASE_PROJECT_ID would silently accept ANY bearer token. Warn loudly on
  // every non-test deployment so a misconfiguration is visible in the logs.
  if (
    options.verifyToken === undefined &&
    options.env.FIREBASE_PROJECT_ID === undefined &&
    options.env.NODE_ENV !== 'test'
  ) {
    app.log.warn(
      'SECURITY: FIREBASE_PROJECT_ID is not set — using the INSECURE dev token ' +
        'verifier (ANY bearer token is accepted as a user id). Set ' +
        'FIREBASE_PROJECT_ID for every hosted/non-local deployment.',
    );
  }

  // DB is created first: both the gateway's member resolver and the route auth
  // hook need it. Routes that need persistence stay gated behind DATABASE_URL
  // so tests that only touch health/gateway keep running without one.
  let dbHandle: DatabaseHandle | undefined;
  if (options.env.DATABASE_URL !== undefined) {
    dbHandle = createDatabase({ url: options.env.DATABASE_URL });
    const handle = dbHandle;
    app.addHook('onClose', async () => {
      await handle.sql.end();
    });
  }

  const gatewayOptions: ConvoyGatewayOptions = { ...options.gateway };
  if (dbHandle !== undefined) {
    if (gatewayOptions.resolveMember === undefined) {
      gatewayOptions.resolveMember = createMemberResolver(
        dbHandle.db,
        verifyToken,
      );
    }
    if (gatewayOptions.resolveLeader === undefined) {
      gatewayOptions.resolveLeader = createLeaderResolver(dbHandle.db);
    }
    if (gatewayOptions.positionStore === undefined) {
      gatewayOptions.positionStore = createDbPositionStore(dbHandle.db);
    }
  }
  if (options.env.REDIS_URL !== undefined) {
    const { RedisFanout } = await import('./realtime/redis_fanout.js');
    const redisFanout = new RedisFanout(options.env.REDIS_URL);
    await redisFanout.connect();
    app.addHook('onClose', async () => {
      await redisFanout.close();
    });
    gatewayOptions.fanout = redisFanout;
  } else if (gatewayOptions.snapshotStore === undefined) {
    // Single-instance only: in-memory hazard/route/waypoint snapshot for late
    // joiners. With RedisFanout (multi-instance) a per-process snapshot would
    // be incomplete, so it's left off until backed by shared state.
    gatewayOptions.snapshotStore = createInMemorySnapshotStore();
  }
  await app.register(createConvoyGateway(gatewayOptions));

  if (dbHandle !== undefined) {
    const authHook = createAuthHook(dbHandle.db, verifyToken);
    await app.register(createConvoyRoutes({ db: dbHandle, authHook }));
    await app.register(createVehicleRoutes({ db: dbHandle, authHook }));
    await app.register(
      createPttRoutes({ db: dbHandle, env: options.env, authHook }),
    );
  }

  return app;
}
