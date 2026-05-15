# Crew Link

Flutter-Mobile-App für Konvoi-Koordination: Echtzeit-GPS, Push-to-Talk, CarPlay.

## Struktur (Feature-First)

```
lib/
  app/                          # App-Root (MaterialApp, Routing)
  core/                         # Shared infrastructure
    config/                       # Endpoints, env
    models/                       # Domain models (Convoy, GpsUpdate, ...)
    realtime/                     # WebSocket-Clients (GPS, PTT)
  features/
    convoy/
      data/                       # REST/WS-Clients spezifisch
      domain/                     # Use-cases
      presentation/               # Screens, Widgets
    gps/
    ptt/
    vehicle_profile/
test/
```

## Aktive Regeln (auszug)

- Backend trennt REST (CRUD) und WebSocket/WebRTC (Realtime).
- GPS läuft ausschließlich über WebSocket-Channel pro Konvoi.
- PTT nutzt WebRTC mit SFU.
- Persistenz: PostgreSQL + PostGIS.
- Dart: Effective Dart + `dart format`.

## Setup

```
flutter pub get
flutter analyze
flutter test
flutter run
```
