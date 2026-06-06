# Backend-Deployment

Das Backend (`backend/`, Fastify + Drizzle/PostGIS + Redis + LiveKit) deployen,
damit Konvoi erstellen/beitreten, Live-GPS-Sharing und Push-to-Talk in der App
funktionieren. Geht weitgehend über **Gratis-Stufen**.

## Überblick — was wo läuft

| Komponente | Dienst (Gratis-Stufe) | Liefert |
|---|---|---|
| Postgres + PostGIS | **Supabase** | `DATABASE_URL` |
| Redis (optional) | **Upstash** | `REDIS_URL` |
| LiveKit (PTT) | **LiveKit Cloud** | `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET` |
| Backend-Server | **Render** (oder Railway/Fly) | öffentliche `https://…`-URL |

> 🔐 **Auth:** Das Backend verifiziert echte Firebase-ID-Token (Projekt
> `crew-link-3c852`) und nutzt die Firebase-UID als stabile User-/Member-ID.
> **Produktion MUSS `FIREBASE_PROJECT_ID` setzen** (idealerweise auch
> `NODE_ENV=production`) — sonst fällt der Server auf den unsicheren Dev-Verifier
> zurück, der jedes Bearer-Token als gültige Identität akzeptiert. Startet der
> Server ohne `FIREBASE_PROJECT_ID`, warnt der Log laut.

---

## 1. Postgres + PostGIS (Supabase)

1. [supabase.com](https://supabase.com) → **New project** (Region nah an dir, Passwort merken).
2. **Project Settings → Database → Connection string → URI** kopieren — das ist deine `DATABASE_URL`.
   - Nutze die **Direct connection** (Port 5432) für die Migration; für die laufende
     App ist auch der **Session/Transaction Pooler** (Port 6543) ok.
3. PostGIS musst du nicht von Hand aktivieren — die Migration macht
   `CREATE EXTENSION IF NOT EXISTS postgis` selbst.

## 2. Redis (Upstash) — optional

Für **eine** Backend-Instanz nicht nötig (in-process Fan-out reicht). Für später:
1. [upstash.com](https://upstash.com) → **Create Database** (Redis).
2. Die **`rediss://…`-URL** kopieren → `REDIS_URL`.

## 3. LiveKit (PTT)

1. [cloud.livekit.io](https://cloud.livekit.io) → Projekt anlegen.
2. Aus den **Settings/Keys**: `LIVEKIT_URL` (wss://…), `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`.

## 4. Migration einspielen (einmalig)

Am einfachsten lokal von deinem PC (Node läuft lokal, kein Pfad-Problem):

```sh
cd backend
# Windows PowerShell:
$env:DATABASE_URL="<deine-supabase-direct-url>"; npm run db:migrate
# macOS/Linux:
DATABASE_URL="<deine-supabase-direct-url>" npm run db:migrate
```

Das legt Schema (users, vehicles, convoys, geo) an und aktiviert PostGIS.

## 5. Backend deployen (Render, via Docker)

1. [render.com](https://render.com) → **New → Web Service** → dein GitHub-Repo
   `OsuGerman/Crew-Link` verbinden.
2. **Root Directory:** `backend` · **Runtime:** Docker (das `backend/Dockerfile`
   wird genutzt) · **Health Check Path:** `/health`.
3. **Environment** setzen:
   ```
   NODE_ENV = production
   FIREBASE_PROJECT_ID = crew-link-3c852
   DATABASE_URL = <Supabase-URL>
   LIVEKIT_URL = wss://…
   LIVEKIT_API_KEY = …
   LIVEKIT_API_SECRET = …
   # optional:
   REDIS_URL = rediss://…
   ```
   (`PORT`/`HOST` setzt Render selbst; der Server liest `PORT`.)
   **`FIREBASE_PROJECT_ID` ist Pflicht** — ohne läuft der unsichere Dev-Verifier.
4. Deploy. Danach hast du eine URL wie `https://crew-link-backend.onrender.com`.

> Render-Gratis-Stufe schläft bei Inaktivität ein → erster Request nach Pause ist
> langsam (Cold Start). Für Tests ok.

## 6. App auf das Backend zeigen

Die App liest die Backend-URL aus `--dart-define` (sonst `localhost`). Beim
APK-/IPA-Bau:

```
--dart-define=CREW_LINK_API_URL=https://crew-link-backend.onrender.com
--dart-define=CREW_LINK_WS_URL=wss://crew-link-backend.onrender.com
```

(REST über `https`, WebSocket über `wss` — bei Render dieselbe Host-Adresse.)
Den CI-APK-Workflow erweitere ich so, dass er diese URL als Eingabe annimmt.

---

## Reihenfolge

1. Supabase + LiveKit anlegen, URLs/Keys sammeln.
2. `npm run db:migrate` lokal gegen die Supabase-URL.
3. Backend auf Render deployen (Env-Vars setzen).
4. App mit den `--dart-define`s bauen (der Android-APK-Workflow nimmt `api_url`/
   `ws_url` als Eingaben) und Konvoi/GPS/PTT testen. Echte Firebase-Token-
   Verifizierung ist im Backend bereits aktiv (`FIREBASE_PROJECT_ID` setzen).
