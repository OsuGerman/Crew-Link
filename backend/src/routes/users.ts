import type { FastifyPluginAsync, preHandlerHookHandler } from 'fastify';

import type { DatabaseHandle } from '../db/client.js';
import { deleteUserAccount } from '../services/users.js';

const HTTP_NO_CONTENT = 204;

export interface UserRoutesOptions {
  db: DatabaseHandle;
  authHook: preHandlerHookHandler;
}

export function createUserRoutes(
  options: UserRoutesOptions,
): FastifyPluginAsync {
  return async (app) => {
    app.addHook('preHandler', options.authHook);

    // GDPR / Play Store account deletion. Removes the user, their vehicle, their
    // convoy memberships, and the convoys they own (members of those return to
    // the lobby). The matching Firebase Auth user is deleted client-side after
    // this returns 204.
    app.delete('/users/me', async (req, reply) => {
      await deleteUserAccount(options.db.db, req.authUser!.id);
      return reply.code(HTTP_NO_CONTENT).send();
    });
  };
}
