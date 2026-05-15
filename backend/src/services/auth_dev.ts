import type { FastifyReply, FastifyRequest, preHandlerHookHandler } from 'fastify';

import type { Database } from '../db/client.js';
import { users, type User } from '../db/schema/users.js';

declare module 'fastify' {
  interface FastifyRequest {
    authUser?: { id: string; displayName: string };
  }
}

const HTTP_UNAUTHORIZED = 401;
const BEARER_PATTERN = /^Bearer\s+(.+)$/i;

const DEV_NAME_PREFIX = 'Dev';
const DEV_NAME_SHORT_ID_LEN = 6;

// Dev-only auth: the bearer token is treated as the `apple_user_id`
// directly. On first contact for a token we upsert a user row so the
// rest of the system can rely on foreign keys. Real Sign-in-with-Apple
// replaces this hook in `routes/convoys.ts` by injecting a different
// resolver.
export async function getOrCreateDevUser(
  db: Database,
  token: string,
): Promise<User> {
  const displayName = `${DEV_NAME_PREFIX} ${token.slice(0, DEV_NAME_SHORT_ID_LEN)}`;
  const [user] = await db
    .insert(users)
    .values({
      appleUserId: token,
      displayName,
    })
    .onConflictDoUpdate({
      target: users.appleUserId,
      set: { updatedAt: new Date() },
    })
    .returning();
  if (!user) {
    throw new Error('user upsert returned no row');
  }
  return user;
}

/// Fastify preHandler that resolves a Bearer token into an authenticated
/// user (auto-upserting them in the dev stub) and attaches it to the
/// request as `req.authUser`. Replace this when real Sign-in-with-Apple
/// + JWT verification lands.
export function createDevAuthHook(db: Database): preHandlerHookHandler {
  return async (req: FastifyRequest, reply: FastifyReply) => {
    const header = req.headers.authorization ?? '';
    const match = BEARER_PATTERN.exec(header);
    const token = match?.[1]?.trim() ?? '';
    if (token.length === 0) {
      return reply.code(HTTP_UNAUTHORIZED).send({ error: 'unauthorized' });
    }
    const user = await getOrCreateDevUser(db, token);
    req.authUser = { id: user.id, displayName: user.displayName };
  };
}
