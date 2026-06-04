# syntax=docker/dockerfile:1
# Crew Link backend — Fastify + Drizzle/Postgres(+PostGIS) + Redis + LiveKit.
# Build context is this `backend/` directory.

# ── build stage ──────────────────────────────────────────────────────────────
FROM node:22-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

# ── runtime stage ────────────────────────────────────────────────────────────
FROM node:22-slim AS runtime
WORKDIR /app
ENV NODE_ENV=production
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force
# Compiled server + the SQL migrations (tsc does not copy *.sql), so the schema
# can also be applied in-container via `node dist/db/migrate.js`.
COPY --from=build /app/dist ./dist
COPY --from=build /app/src/db/migrations ./dist/db/migrations
EXPOSE 3000
CMD ["node", "dist/index.js"]
