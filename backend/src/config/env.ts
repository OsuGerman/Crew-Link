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
});

export type Env = z.infer<typeof envSchema>;

export function loadEnv(
  source: Record<string, string | undefined> = process.env,
): Env {
  return envSchema.parse(source);
}
