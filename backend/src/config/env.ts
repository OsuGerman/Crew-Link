import { z } from 'zod';

const PORT_MIN = 1;
const PORT_MAX = 65535;
const DEFAULT_PORT = 3000;

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().min(PORT_MIN).max(PORT_MAX).default(DEFAULT_PORT),
  HOST: z.string().min(1).default('0.0.0.0'),
  LOG_LEVEL: z
    .enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace'])
    .default('info'),
  DATABASE_URL: z.string().url().optional(),
  REDIS_URL: z.string().url().optional(),
  LIVEKIT_URL: z.string().url().optional(),
  LIVEKIT_API_KEY: z.string().min(1).optional(),
  LIVEKIT_API_SECRET: z.string().min(1).optional(),
  // Firebase project id — when set, the backend verifies real Firebase ID
  // tokens (issuer/audience + Google JWKS) and uses the Firebase UID as the
  // stable user identity. When unset (local dev / integration tests), the
  // bearer token is treated as the user id directly.
  FIREBASE_PROJECT_ID: z.string().min(1).optional(),
});

export type Env = z.infer<typeof envSchema>;

export function loadEnv(
  source: Record<string, string | undefined> = process.env,
): Env {
  return envSchema.parse(source);
}
