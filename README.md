# Crew Link

Konvoi-Koordination für Fahrzeuggruppen: Live-GPS-Karte, automatische Abstandswarnung, CarPlay-eingebettetes Walkie-Talkie, Fahrzeugprofile.

## Monorepo Layout

```
crew_link/
├── app/         # Flutter iOS-App (Dart, Riverpod, Freezed)
├── backend/     # Fastify + TypeScript + Drizzle/PostGIS
├── infra/       # docker-compose (Postgres+PostGIS), Terraform (TBD)
├── .github/     # CI workflows
└── flutter/     # Vendored Flutter SDK — local Windows dev only (gitignored)
```

## Quickstart

### Flutter app
```sh
cd app
flutter pub get
flutter analyze
flutter test
```

On Windows the vendored SDK lives at `flutter/bin/flutter.bat`. Prepend it to `PATH` once per session:
```powershell
$env:PATH = "$PWD\..\flutter\bin;$env:PATH"
```

### Backend
```sh
cd backend
npm install
npm test
```

### Local Postgres + PostGIS
```sh
cd infra
docker compose up -d
```

## Architecture rules

- REST (CRUD) and WebSocket/WebRTC (realtime) live in separate layers in `backend/src/`.
- GPS updates flow **exclusively** over a WebSocket channel per convoy — no polling.
- Push-to-Talk uses WebRTC with an SFU (mediasoup) for scalable audio fan-out.
- Persistence: PostgreSQL + PostGIS only.
- Flutter follows feature-first folder layout under `app/lib/features/`.
- Endpoints are spec-first (OpenAPI/JSON-Schema) before implementation.
- TDD: tests precede production code in both `app/` and `backend/`.
