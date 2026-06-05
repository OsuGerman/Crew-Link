import type { FastifyPluginAsync, preHandlerHookHandler } from 'fastify';
import { z } from 'zod';

import type { DatabaseHandle } from '../db/client.js';
import {
  deleteUserVehicle,
  getUserVehicle,
  setUserVehicle,
} from '../services/vehicles.js';

const NAME_MAX_LEN = 120;
const COLOR_MAX_LEN = 60;
const MOD_NAME_MAX_LEN = 80;
const MOD_DESC_MAX_LEN = 240;
const MOD_CATEGORY_MAX_LEN = 40;
const MAX_MODS = 30;
const YEAR_LOWER = 1900;
const YEAR_UPPER_OFFSET = 2;
const POWER_KW_MAX = 5000;
const DRIVETRAIN_MAX_LEN = 8;
const DISPLACEMENT_MAX = 20000;
const TRANSMISSION_MAX_LEN = 16;
const HTTP_BAD_REQUEST = 400;
const HTTP_NO_CONTENT = 204;

const yearMax = new Date().getFullYear() + YEAR_UPPER_OFFSET;

const modSchema = z.object({
  name: z.string().min(1).max(MOD_NAME_MAX_LEN),
  description: z.string().max(MOD_DESC_MAX_LEN).optional(),
  category: z.string().max(MOD_CATEGORY_MAX_LEN).optional(),
});

const putBodySchema = z.object({
  make: z.string().min(1).max(NAME_MAX_LEN),
  model: z.string().min(1).max(NAME_MAX_LEN),
  year: z.number().int().min(YEAR_LOWER).max(yearMax).optional(),
  color: z.string().min(1).max(COLOR_MAX_LEN).optional(),
  // Optional spec sheet (snake_case keys match the app's wire format).
  power_kw: z.number().int().min(0).max(POWER_KW_MAX).optional(),
  drivetrain: z.string().min(1).max(DRIVETRAIN_MAX_LEN).optional(),
  displacement: z.number().int().min(0).max(DISPLACEMENT_MAX).optional(),
  transmission_type: z.string().min(1).max(TRANSMISSION_MAX_LEN).optional(),
  mods: z.array(modSchema).max(MAX_MODS).optional(),
});

export interface VehicleRoutesOptions {
  db: DatabaseHandle;
  authHook: preHandlerHookHandler;
}

export function createVehicleRoutes(
  options: VehicleRoutesOptions,
): FastifyPluginAsync {
  return async (app) => {
    app.addHook('preHandler', options.authHook);

    app.get('/vehicles/me', async (req, reply) => {
      const vehicle = await getUserVehicle(options.db.db, req.authUser!.id);
      return reply.send(vehicle);
    });

    app.put('/vehicles/me', async (req, reply) => {
      const result = putBodySchema.safeParse(req.body);
      if (!result.success) {
        return reply
          .code(HTTP_BAD_REQUEST)
          .send({ error: 'invalid body', issues: result.error.issues });
      }
      const v = result.data;
      const vehicle = await setUserVehicle(options.db.db, req.authUser!.id, {
        make: v.make,
        model: v.model,
        year: v.year,
        color: v.color,
        powerKw: v.power_kw,
        drivetrain: v.drivetrain,
        displacement: v.displacement,
        transmissionType: v.transmission_type,
        mods: v.mods,
      });
      return reply.send(vehicle);
    });

    app.delete('/vehicles/me', async (req, reply) => {
      await deleteUserVehicle(options.db.db, req.authUser!.id);
      return reply.code(HTTP_NO_CONTENT).send();
    });
  };
}
