import { defineConfig } from 'drizzle-kit';

const FALLBACK_URL = 'postgres://postgres:postgres@localhost:5432/crew_link';

export default defineConfig({
  dialect: 'postgresql',
  schema: './src/db/schema/index.ts',
  out: './src/db/migrations',
  dbCredentials: {
    url: process.env.DATABASE_URL ?? FALLBACK_URL,
  },
  strict: true,
  verbose: true,
});
