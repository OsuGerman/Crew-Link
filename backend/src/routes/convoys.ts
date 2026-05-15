import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';

import type { DatabaseHandle } from '../db/client.js';
import { createDevAuthHook } from '../services/auth_dev.js';
import {
  ConvoyNotFoundError,
  NotConvoyOwnerError,
  createConvoy,
  InviteCodeNotFoundError,
  joinConvoy,
  leaveConvoy,
  setConvoyDestination,
} from '../services/convoys.js';

const PROXIMITY_MIN_M = 50;
const PROXIMITY_MAX_M = 10000;
const PROXIMITY_DEFAULT_M = 500;
const NAME_MAX_LEN = 120;
const INVITE_MAX_LEN = 32;
const LABEL_MAX_LEN = 120;
const HTTP_CREATED = 201;
const HTTP_NO_CONTENT = 204;
const HTTP_NOT_FOUND = 404;
const HTTP_FORBIDDEN = 403;
const HTTP_BAD_REQUEST = 400;

const createBodySchema = z.object({
  name: z.string().min(1).max(NAME_MAX_LEN),
  proximityWarningMeters: z
    .number()
    .int()
    .min(PROXIMITY_MIN_M)
    .max(PROXIMITY_MAX_M)
    .default(PROXIMITY_DEFAULT_M),
});

const joinBodySchema = z.object({
  inviteCode: z.string().min(1).max(INVITE_MAX_LEN),
});

const destinationSchema = z.object({
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
  label: z.string().max(LABEL_MAX_LEN).optional(),
});

const patchBodySchema = z.object({
  destination: destinationSchema.nullable(),
});

export interface ConvoyRoutesOptions {
  db: DatabaseHandle;
}

export function createConvoyRoutes(
  options: ConvoyRoutesOptions,
): FastifyPluginAsync {
  return async (app) => {
    app.addHook('preHandler', createDevAuthHook(options.db.db));

    app.post('/convoys', async (req, reply) => {
      const result = createBodySchema.safeParse(req.body);
      if (!result.success) {
        return reply
          .code(HTTP_BAD_REQUEST)
          .send({ error: 'invalid body', issues: result.error.issues });
      }
      const convoy = await createConvoy(options.db.db, {
        ownerUserId: req.authUser!.id,
        name: result.data.name,
        proximityWarningMeters: result.data.proximityWarningMeters,
      });
      return reply.code(HTTP_CREATED).send(convoy);
    });

    app.post('/convoys/join', async (req, reply) => {
      const result = joinBodySchema.safeParse(req.body);
      if (!result.success) {
        return reply
          .code(HTTP_BAD_REQUEST)
          .send({ error: 'invalid body', issues: result.error.issues });
      }
      try {
        const convoy = await joinConvoy(options.db.db, {
          userId: req.authUser!.id,
          inviteCode: result.data.inviteCode,
        });
        return reply.send(convoy);
      } catch (err) {
        if (err instanceof InviteCodeNotFoundError) {
          return reply
            .code(HTTP_NOT_FOUND)
            .send({ error: 'invite code not found' });
        }
        throw err;
      }
    });

    app.delete<{ Params: { convoyId: string } }>(
      '/convoys/:convoyId/membership',
      async (req, reply) => {
        await leaveConvoy(options.db.db, {
          userId: req.authUser!.id,
          convoyId: req.params.convoyId,
        });
        return reply.code(HTTP_NO_CONTENT).send();
      },
    );

    app.patch<{ Params: { convoyId: string } }>(
      '/convoys/:convoyId',
      async (req, reply) => {
        const result = patchBodySchema.safeParse(req.body);
        if (!result.success) {
          return reply
              .code(HTTP_BAD_REQUEST)
              .send({ error: 'invalid body', issues: result.error.issues });
        }
        try {
          const updated = await setConvoyDestination(options.db.db, {
            userId: req.authUser!.id,
            convoyId: req.params.convoyId,
            destination: result.data.destination === null
                ? null
                : {
                    lat: result.data.destination.lat,
                    lng: result.data.destination.lng,
                    label: result.data.destination.label ?? null,
                  },
          });
          return reply.send(updated);
        } catch (err) {
          if (err instanceof ConvoyNotFoundError) {
            return reply.code(HTTP_NOT_FOUND).send({ error: 'convoy not found' });
          }
          if (err instanceof NotConvoyOwnerError) {
            return reply.code(HTTP_FORBIDDEN).send({ error: 'not the convoy owner' });
          }
          throw err;
        }
      },
    );
  };
}
