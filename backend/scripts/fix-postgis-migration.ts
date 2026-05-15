import { readdir, readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// drizzle-kit wraps custom column types declared via customType.dataType()
// in double quotes (`"geography(Point, 4326)"`). Postgres then reads that
// as a quoted identifier and the migration fails with
// `type "geography(Point, 4326)" does not exist`. This script strips the
// quotes around any geo type, leaving every other identifier untouched.
//
// Run after `drizzle-kit generate`. Idempotent.

const MIGRATIONS_DIR = resolve(
  fileURLToPath(import.meta.url),
  '..',
  '..',
  'src',
  'db',
  'migrations',
);

const GEO_TYPE_PATTERN = /"(geography|geometry)\(([^"]+?)\)"/g;

async function main(): Promise<void> {
  const entries = await readdir(MIGRATIONS_DIR);
  const sqlFiles = entries.filter((name) => name.endsWith('.sql'));

  let totalReplacements = 0;
  for (const name of sqlFiles) {
    const file = resolve(MIGRATIONS_DIR, name);
    const original = await readFile(file, 'utf8');
    let replacements = 0;
    const fixed = original.replace(GEO_TYPE_PATTERN, (_match, kind, args) => {
      replacements += 1;
      return `${kind as string}(${args as string})`;
    });
    if (replacements > 0) {
      await writeFile(file, fixed, 'utf8');
      totalReplacements += replacements;
      // eslint-disable-next-line no-console
      console.log(`patched ${name}: ${replacements} PostGIS type(s) unquoted`);
    }
  }
  if (totalReplacements === 0) {
    // eslint-disable-next-line no-console
    console.log('no PostGIS type quoting to fix');
  }
}

main().catch((err: unknown) => {
  // eslint-disable-next-line no-console
  console.error('fix-postgis-migration failed', err);
  process.exit(1);
});
