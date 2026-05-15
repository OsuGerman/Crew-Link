# Crew Link Backend

Node.js + Fastify + TypeScript backend for the Crew Link convoy app.

## Stack

- **Fastify 5** — HTTP routing, WebSocket (later via `@fastify/websocket`)
- **Drizzle ORM 0.45** + postgres-js 3.4 — DB access; schemas under `src/db/schema/`
- **drizzle-kit 0.31** — migration generation (`npm run db:generate`)
- **PostgreSQL 16 + PostGIS 3.4** — local instance via `infra/docker-compose.yml`; CI runs the same image as a service
- **Vitest** — test runner (Fastify's `app.inject()` for HTTP tests, no network)
- **Zod** — env + schema validation
- **TypeScript strict** — `noUncheckedIndexedAccess`, `noUnusedLocals`, `noUnusedParameters`

## Database

Tables (see `src/db/schema/`):

- `users` — Sign in with Apple subject, display name, email
- `vehicles` + `vehicle_mods` — user-owned cars and their mods
- `convoys` — convoy metadata, invite code, status (`lobby`/`active`/`ended`), `proximity_threshold_m` default 500
- `convoy_members` — join table with optional `last_known_position geography(Point, 4326)` (PostGIS)

### Workflow

```sh
# Start local Postgres+PostGIS
cd ../infra && docker compose up -d

# Generate a new migration after schema changes
cd ../backend && npm run db:generate

# Apply pending migrations (enables postgis extension first)
DATABASE_URL=postgres://postgres:postgres@localhost:5432/crew_link npm run db:migrate
```

> **PostGIS gotcha:** drizzle-kit wraps custom column types in double quotes, which Postgres reads as an identifier. After generating a migration that touches a `geography(...)` column, drop the quotes around the type — see migration `0000_polite_pestilence.sql` for the expected form.

### Tests

Integration tests under `test/db/` need a reachable Postgres. They skip automatically when `DATABASE_URL` is not set; CI provides one via a service container.

## Setup

```sh
npm install
cp .env.example .env
npm run dev
```

## Scripts

| Command            | Purpose                          |
| ------------------ | -------------------------------- |
| `npm run dev`      | Hot-reload dev server (tsx)      |
| `npm run build`    | Compile to `dist/`               |
| `npm start`        | Run compiled output              |
| `npm test`         | Run vitest once                  |
| `npm run test:watch` | Watch-mode tests               |
| `npm run typecheck`  | TypeScript without emit        |
| `npm run format`     | Prettier write                 |
| `npm run db:generate`| Generate migration from schema |
| `npm run db:migrate` | Apply pending migrations       |
| `npm run db:push`    | Sync schema directly (dev)     |

## Layout

```
src/
  config/env.ts            # Zod-validated process env (incl. DATABASE_URL)
  routes/health.ts         # GET /health
  realtime/                # WebSocket gateway (next tasks)
  services/                # Domain services (next tasks)
  db/
    schema/                # Drizzle table definitions
    migrations/            # drizzle-kit output
    client.ts              # createDatabase(): postgres+drizzle handle
    migrate.ts             # applyMigrations() + CLI entry
  server.ts                # buildApp() factory — testable Fastify instance
  index.ts                 # Process entry, listens on PORT
test/
  routes/health.test.ts
  db/schema.test.ts        # Integration tests, skip without DATABASE_URL
```

## Conventions

- TDD: tests live in `test/`, mirror `src/` paths. Write the test before the implementation.
- All HTTP routes are Fastify plugins. Tests use `app.inject()`, no real socket.
- Env is loaded once via `loadEnv()`; never read `process.env` directly outside `config/env.ts`.
