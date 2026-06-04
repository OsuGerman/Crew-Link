# Crew Link

Konvoi-Koordination für Fahrzeuggruppen: Live-GPS-Karte, automatische Abstandswarnung, Push-to-Talk und CarPlay. Flutter-App (iOS/Android) mit einem Fastify/PostGIS-Backend.

![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20Android%20%7C%20CarPlay-1a1a1a?style=flat-square)
![Flutter](https://img.shields.io/badge/Flutter-3.41-02569B?style=flat-square&logo=flutter)
![License](https://img.shields.io/badge/license-proprietary-lightgrey?style=flat-square)

## Worum geht's

Crew Link hält Fahrzeuggruppen auf gemeinsamen Touren zusammen — Motorrad-Touren, Roadtrips, Off-Road-Crews. Ein Teilnehmer startet einen Konvoi, alle anderen treten per Link oder Code bei. Die App zeigt jeden live auf der Karte, warnt automatisch wenn jemand zurückfällt, und bietet eine Push-to-Talk-Funkverbindung, die auch über CarPlay funktioniert.

## Features

- **Live-Konvoi-Karte** — alle Teilnehmer in Echtzeit auf einer MapLibre-Karte. Updates laufen über WebSocket, nicht über Polling.
- **Abstandswarnung** — fällt jemand zu weit zurück, bekommen Hintermann und Konvoi-Leader eine Push-Notification.
- **Push-to-Talk** — WebRTC mit LiveKit-SFU, bedienbar per Touchscreen oder CarPlay-Taste.
- **CarPlay** — Karte und PTT auf dem Fahrzeug-Display, über eine Swift-Bridge an die Dart-Seite angebunden.
- **Konvoi-Lifecycle** — erstellen, per Code beitreten, verlassen. REST-API; das Apple-Sign-In-Token wird zum Realtime-Gateway durchgereicht.
- **Fahrzeugprofile** — mehrere Fahrzeuge pro Nutzer; das aktive Profil bestimmt Standard-Abstand und Karten-Avatar.
- **Backend** — Fastify mit Drizzle/PostGIS für Geo-Queries, Redis-Fanout für horizontal skalierbare WebSockets.

## Projektstruktur

```
app/        Flutter-App (Riverpod, Freezed, MapLibre), inkl. nativem iOS-/Android-Code
backend/    Fastify + TypeScript: REST-Routen, WebSocket-Gateway, Drizzle-Schema/PostGIS
infra/      docker-compose für Postgres + PostGIS
fastlane/   iOS-Release (TestFlight, App Store)
docs/       Landing-Page und Datenschutz
.github/    CI-Workflows
```

## Entwicklung

Flutter-App:

```sh
cd app
flutter pub get
flutter analyze
flutter test
flutter run
```

Unter Windows liegt eine vendored Flutter-SDK unter `flutter/bin/flutter.bat`.

Backend:

```sh
cd backend
npm install
npm test
npm run dev
```

Lokale Datenbank:

```sh
cd infra && docker compose up -d
cd ../backend && npm run db:generate && npm run db:migrate
```

## Architektur

Die Flutter-App und die CarPlay-Bridge sprechen mit dem Fastify-Backend über drei Kanäle: REST für Auth und Konvoi-Lifecycle, WebSocket für den GPS-Stream, WebRTC für Push-to-Talk. Persistiert wird in Postgres mit PostGIS; das Audio-Fan-out übernimmt ein LiveKit-SFU; Redis verteilt WebSocket-Events über mehrere Backend-Instanzen.

Konventionen im Repo: REST und Realtime liegen in getrennten Layern, GPS-Updates fließen ausschließlich über WebSocket, die Flutter-Seite ist feature-first unter `app/lib/features/` organisiert, und Tests entstehen vor dem Produktionscode.

## Plattform-Status

| Plattform | Stand |
|-----------|-------|
| iOS       | Build grün, TestFlight-Pipeline via Fastlane — siehe [TESTFLIGHT.md](TESTFLIGHT.md) |
| Android   | Build grün, Play-Store-Listing noch offen |
| CarPlay   | Bridge implementiert, Apple-Approval offen |
| Web       | Demo-Preview über `main_web_preview.dart` mit Mock-Backend |

## Dev-Sideload ohne bezahlten Apple-Account

Der Workflow `.github/workflows/altstore-ipa.yml` baut auf Knopfdruck eine unsignierte IPA, die sich per [AltStore](https://altstore.io) mit einer kostenlosen Apple-ID aufs eigene iPhone sideloaden lässt:

1. GitHub → Actions → "AltStore IPA" → Run workflow
2. Artifact herunterladen und in der AltStore-App auf dem iPhone installieren
3. Profil unter Einstellungen → Allgemein → VPN & Geräteverwaltung vertrauen

Der Workflow strippt dafür Free-Tier-inkompatible Entitlements (Sign-In, Push, CarPlay, App-Groups), entfernt die CarPlay-Scene aus der Info.plist und schreibt die Bundle-ID auf `de.crewlink.app.altstore` um.

Wichtig: Crew Link bindet viele native Frameworks ein (Firebase, WebRTC/LiveKit, MapLibre). Auf manchen Geräten beendet iOS eine mit kostenloser Apple-ID signierte App direkt beim Start, ohne Crash-Log zu schreiben. Zuverlässig läuft iOS erst mit einem bezahlten Apple-Developer-Account (TestFlight oder Ad-Hoc mit registrierter Geräte-UDID). Zum reinen Durchklicken der UI eignet sich der Demo-Build (`lib/main_web_preview.dart`, gemockt) — auch als Android-APK.

## Setup vor dem Geräte-Betrieb

Der Code greift mit gesetzten Credentials sofort und degradiert ohne sie sauber (kein Start-Crash):

| Bereich | Einrichtung | ohne Setup |
|---------|-------------|------------|
| Firebase (Auth, FCM, Crashlytics, Analytics) | `flutterfire configure --project=crew-link` | Platzhalter; `Firebase.initializeApp` ist in try/catch gekapselt, Firebase-Features bleiben aus |
| Android-Release-Signing | Env-Vars `RELEASE_KEYSTORE_FILE`, `RELEASE_STORE_PASSWORD`, `RELEASE_KEY_ALIAS`, `RELEASE_KEY_PASSWORD` | Fallback auf Debug-Key (nicht Play-tauglich) |
| iOS-Signing | `DEVELOPMENT_TEAM` in der Xcode-Config plus Apple-Secrets für TestFlight | Archive/Upload erfordert manuelle Team-Wahl |
| CarPlay | Apple-Approval für `carplay-communication` | Bridge implementiert, Review offen |

Das Hintergrund-Tracking stuft die Standort-Berechtigung beim Konvoi-Beitritt auf "Always" hoch und nutzt auf Android einen Foreground-Service, damit die Position auch im Hintergrund oder bei gesperrtem Display weiterläuft.

## Release-Pipeline

| Workflow | Trigger | Ergebnis |
|----------|---------|----------|
| CI | jeder Push | Flutter- und Backend-Tests, iOS-/Android-Builds |
| TestFlight | manuell oder wöchentlich | signierte IPA → App Store Connect |
| AltStore IPA | manuell | unsignierte IPA als Artifact |

Details zum TestFlight-Setup (Fastlane, Match, CarPlay-Approval) stehen in [TESTFLIGHT.md](TESTFLIGHT.md).

## Tech-Stack

- **Mobile:** Flutter 3.41, Dart 3.11, Riverpod, Freezed, go_router, MapLibre, Firebase (Auth, Crashlytics, FCM), LiveKit, WebRTC, Sentry
- **Nativ:** Swift (CarPlay-Bridge), Kotlin
- **Backend:** Node.js, Fastify, TypeScript, Drizzle ORM, Pino, Vitest
- **Daten & Infra:** PostgreSQL mit PostGIS, Redis, Docker Compose
- **Release:** Fastlane, GitHub Actions

## Lizenz

Proprietär, © 2026 Crew Link. Der Code ist öffentlich einsehbar, aber nicht zur kommerziellen Wiederverwertung freigegeben.
