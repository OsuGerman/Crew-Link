import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    globals: false,
    environment: 'node',
    include: ['test/**/*.test.ts'],
    // DB-Integrationstests teilen sich dieselbe Postgres-Instanz und rufen je
    // applyMigrations() in beforeAll. Parallele Test-Dateien rennen dabei in
    // einen Race auf die __drizzle_migrations-Anlage (duplicate key). Dateien
    // seriell ausfuehren: erste Datei migriert, weitere sehen alles applied.
    fileParallelism: false,
  },
});
