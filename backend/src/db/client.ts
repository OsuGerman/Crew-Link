import { drizzle, type PostgresJsDatabase } from 'drizzle-orm/postgres-js';
import postgres, { type Sql } from 'postgres';

import * as schema from './schema/index.js';

export type Database = PostgresJsDatabase<typeof schema>;

export interface CreateDatabaseOptions {
  url: string;
  max?: number;
}

export interface DatabaseHandle {
  db: Database;
  sql: Sql;
}

const DEFAULT_POOL_SIZE = 10;

export function createDatabase(options: CreateDatabaseOptions): DatabaseHandle {
  const sql = postgres(options.url, {
    max: options.max ?? DEFAULT_POOL_SIZE,
    onnotice: () => {
      // Suppress notices like "extension already exists"; surface via logger
      // when we wire pino-pg in a follow-up.
    },
  });
  const db = drizzle(sql, { schema });
  return { db, sql };
}
