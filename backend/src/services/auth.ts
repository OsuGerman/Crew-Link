import { and, eq, isNull } from 'drizzle-orm';
import type {
  FastifyReply,
  FastifyRequest,
  preHandlerHookHandler,
} from 'fastify';
import { createRemoteJWKSet, jwtVerify } from 'jose';

import type { Database } from '../db/client.js';
import { convoyMembers } from '../db/schema/convoys.js';
import { users, type User } from '../db/schema/users.js';

declare module 'fastify' {
  interface FastifyRequest {
    // `id` = internal users.id (UUID, used for FK writes); `externalId` =
    // stable Firebase UID, used as the external member id everywhere clients
    // see it (REST member.id, WS member id, LiveKit participant identity).
    authUser?: { id: string; externalId: string; displayName: string };
  }
}

const HTTP_UNAUTHORIZED = 401;
const BEARER_PATTERN = /^Bearer\s+(.+)$/i;
const UID_SHORT_LEN = 6;

export interface VerifiedToken {
  uid: string;
  name?: string;
  email?: string;
}

export type TokenVerifier = (token: string) => Promise<VerifiedToken | null>;

/**
 * Local/test verifier: the bearer token IS the user id. Used when no
 * FIREBASE_PROJECT_ID is configured (local dev + integration tests).
 */
export const devTokenVerifier: TokenVerifier = async (token) =>
  token.length > 0 ? { uid: token } : null;

/**
 * Verifies a Firebase ID token against Google's public keys and returns the
 * stable Firebase UID (the `sub` claim). audience = project id, issuer =
 * https://securetoken.google.com/<project-id>.
 */
export function createFirebaseTokenVerifier(projectId: string): TokenVerifier {
  const jwks = createRemoteJWKSet(
    new URL(
      'https://www.googleapis.com/robot/v1/metadata/jwk/securetoken@system.gserviceaccount.com',
    ),
  );
  const issuer = `https://securetoken.google.com/${projectId}`;
  return async (token) => {
    try {
      const { payload } = await jwtVerify(token, jwks, {
        issuer,
        audience: projectId,
      });
      const uid = typeof payload.sub === 'string' ? payload.sub : '';
      if (uid.length === 0) {
        return null;
      }
      return {
        uid,
        name: typeof payload.name === 'string' ? payload.name : undefined,
        email: typeof payload.email === 'string' ? payload.email : undefined,
      };
    } catch {
      return null;
    }
  };
}

function deriveDisplayName(v: VerifiedToken): string {
  if (v.name !== undefined && v.name.length > 0) {
    return v.name;
  }
  if (v.email !== undefined && v.email.length > 0) {
    return v.email.split('@')[0] ?? v.email;
  }
  return `Crew ${v.uid.slice(0, UID_SHORT_LEN)}`;
}

/**
 * Upserts a user keyed by the stable external id (`appleUserId` = Firebase UID
 * in production, or the dev token). Returns the internal user row.
 */
export async function getOrCreateUser(
  db: Database,
  verified: VerifiedToken,
): Promise<User> {
  const [user] = await db
    .insert(users)
    .values({
      appleUserId: verified.uid,
      displayName: deriveDisplayName(verified),
      email: verified.email ?? null,
    })
    .onConflictDoUpdate({
      target: users.appleUserId,
      // Refresh profile from the (verified) token each request so an updated
      // Firebase displayName — set during onboarding — replaces the initial
      // email-derived placeholder in the convoy member list.
      set: {
        updatedAt: new Date(),
        displayName: deriveDisplayName(verified),
        email: verified.email ?? null,
      },
    })
    .returning();
  if (!user) {
    throw new Error('user upsert returned no row');
  }
  return user;
}

/**
 * Fastify preHandler: resolves the Bearer token via [verifyToken] into an
 * authenticated user (upserting on first contact) and attaches it to the
 * request as `req.authUser`.
 */
export function createAuthHook(
  db: Database,
  verifyToken: TokenVerifier,
): preHandlerHookHandler {
  return async (req: FastifyRequest, reply: FastifyReply) => {
    const header = req.headers.authorization ?? '';
    const match = BEARER_PATTERN.exec(header);
    const token = match?.[1]?.trim() ?? '';
    if (token.length === 0) {
      return reply.code(HTTP_UNAUTHORIZED).send({ error: 'unauthorized' });
    }
    const verified = await verifyToken(token);
    if (verified === null) {
      return reply.code(HTTP_UNAUTHORIZED).send({ error: 'unauthorized' });
    }
    const user = await getOrCreateUser(db, verified);
    req.authUser = {
      id: user.id,
      externalId: verified.uid,
      displayName: user.displayName,
    };
  };
}

/**
 * WS-gateway member resolver: verifies the token, confirms the user is a
 * current member of the convoy, and returns the stable external member id
 * (the Firebase UID) — matching `member.id` in the REST convoy payload so the
 * client recognises itself and anti-impersonation lines up.
 */
export function createMemberResolver(
  db: Database,
  verifyToken: TokenVerifier,
): (token: string, convoyId: string) => Promise<string | null> {
  return async (token, convoyId) => {
    const verified = await verifyToken(token);
    if (verified === null) {
      return null;
    }
    const rows = await db
      .select({ id: convoyMembers.id })
      .from(convoyMembers)
      .innerJoin(users, eq(convoyMembers.userId, users.id))
      .where(
        and(
          eq(convoyMembers.convoyId, convoyId),
          eq(users.appleUserId, verified.uid),
          isNull(convoyMembers.leftAt),
        ),
      )
      .limit(1);
    if (rows[0] === undefined) {
      return null;
    }
    return verified.uid;
  };
}

/**
 * WS-gateway leader check: resolves to true iff `memberId` (the already-verified
 * Firebase UID) is the current owner of `convoyId`. Gates leader-only frames
 * (the route/tour). No token verification — the caller resolved the member from
 * a verified token already.
 */
export function createLeaderResolver(
  db: Database,
): (memberId: string, convoyId: string) => Promise<boolean> {
  return async (memberId, convoyId) => {
    const rows = await db
      .select({ role: convoyMembers.role })
      .from(convoyMembers)
      .innerJoin(users, eq(convoyMembers.userId, users.id))
      .where(
        and(
          eq(convoyMembers.convoyId, convoyId),
          eq(users.appleUserId, memberId),
          isNull(convoyMembers.leftAt),
        ),
      )
      .limit(1);
    return rows[0]?.role === 'owner';
  };
}
