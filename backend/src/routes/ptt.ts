import { and, eq, isNull } from 'drizzle-orm';
import type { FastifyPluginAsync } from 'fastify';

import type { Env } from '../config/env.js';
import type { DatabaseHandle } from '../db/client.js';
import { convoyMembers } from '../db/schema/convoys.js';
import { createDevAuthHook } from '../services/auth_dev.js';
import { convoyRoomName, createPttToken } from '../services/livekit_tokens.js';

const HTTP_NOT_FOUND = 404;
const HTTP_SERVICE_UNAVAILABLE = 503;

export interface PttTokenResponse {
  url: string;
  token: string;
  roomName: string;
}

export interface PttRoutesOptions {
  db: DatabaseHandle;
  env: Env;
}

export function createPttRoutes(options: PttRoutesOptions): FastifyPluginAsync {
  return async (app) => {
    app.addHook('preHandler', createDevAuthHook(options.db.db));

    app.post<{ Params: { convoyId: string } }>(
      '/convoys/:convoyId/ptt-token',
      async (req, reply) => {
        const {
          LIVEKIT_URL,
          LIVEKIT_API_KEY,
          LIVEKIT_API_SECRET,
        } = options.env;

        if (
          LIVEKIT_URL === undefined ||
          LIVEKIT_API_KEY === undefined ||
          LIVEKIT_API_SECRET === undefined
        ) {
          return reply
            .code(HTTP_SERVICE_UNAVAILABLE)
            .send({ error: 'livekit not configured' });
        }

        const userId = req.authUser!.id;
        const { convoyId } = req.params;

        const members = await options.db.db
          .select({ id: convoyMembers.id })
          .from(convoyMembers)
          .where(
            and(
              eq(convoyMembers.convoyId, convoyId),
              eq(convoyMembers.userId, userId),
              isNull(convoyMembers.leftAt),
            ),
          )
          .limit(1);

        if (members[0] === undefined) {
          return reply
            .code(HTTP_NOT_FOUND)
            .send({ error: 'not a convoy member' });
        }

        const roomName = convoyRoomName(convoyId);
        const token = await createPttToken({
          apiKey: LIVEKIT_API_KEY,
          apiSecret: LIVEKIT_API_SECRET,
          roomName,
          participantIdentity: userId,
          participantName: req.authUser!.displayName,
        });

        return reply.send({
          url: LIVEKIT_URL,
          token,
          roomName,
        } satisfies PttTokenResponse);
      },
    );
  };
}
