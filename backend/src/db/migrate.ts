import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

import { migrate as drizzleMigrate } from 'drizzle-orm/postgres-js/migrator';

import { loadEnv } from '../config/env.js';
import { createDatabase } from './client.js';

export const MIGRATIONS_FOLDER = resolve(
  dirname(fileURLToPath(import.meta.url)),
  'migrations',
);

export async function applyMigrations(databaseUrl: string): Promise<void> {
  const { db, sql } = createDatabase({ url: databaseUrl, max: 1 });
  try {
    await sql`CREATE EXTENSION IF NOT EXISTS postgis`;
    await drizzleMigrate(db, { migrationsFolder: MIGRATIONS_FOLDER });
  } finally {
    await sql.end();
  }
}

const invokedDirectly =
  process.argv[1] !== undefined &&
  import.meta.url === pathToFileURL(process.argv[1]).href;

if (invokedDirectly) {
  const env = loadEnv();
  if (!env.DATABASE_URL) {
    // eslint-disable-next-line no-console
    console.error('DATABASE_URL is required to run migrations');
    process.exit(1);
  }
  applyMigrations(env.DATABASE_URL).catch((err: unknown) => {
    // eslint-disable-next-line no-console
    console.error('Migration failed', err);
    process.exit(1);
  });
}
