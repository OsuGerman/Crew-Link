# Crew Link

Konvoi-Koordination für Fahrzeuggruppen: Live-GPS-Karte mit nummerierten Positionen, Grün/Gelb/Rot-Abstandswarnung, Leader-Route mit Adresssuche, SOS, Schnellaktionen, Push-to-Talk und CarPlay. Flutter-App (iOS/Android) mit einem Fastify/PostGIS-Backend. In aktiver Entwicklung.

![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20Android%20%7C%20CarPlay-1a1a1a?style=flat-square)
![Flutter](https://img.shields.io/badge/Flutter-3.41-02569B?style=flat-square&logo=flutter)
![License](https://img.shields.io/badge/license-proprietary-lightgrey?style=flat-square)

## Worum geht's

Crew Link hält Fahrzeuggruppen auf gemeinsamen Touren zusammen — Motorrad-Touren, Roadtrips, Off-Road-Crews. Ein Teilnehmer startet einen Konvoi, alle anderen treten per Link oder Code bei. Die App zeigt jeden live auf der Karte, warnt automatisch wenn jemand zurückfällt, und bietet eine Push-to-Talk-Funkverbindung, die auch über CarPlay funktioniert.

## Status

Ein ehrlicher Stand — was läuft, woran gerade gearbeitet wird, was noch offen ist.

**Läuft:**
- Firebase-Auth mit E-Mail/Passwort (Registrieren + Login), Onboarding, Lobby.
- Backend live auf Render (Fastify) mit Konvoi-Lifecycle-REST, Live-GPS-WebSocket-Gateway und echter Firebase-ID-Token-Verifizierung — end-to-end verifiziert (gültiges Token → `201`, ungültiges → `401`).
- Konvoi erstellen/beitreten gegen das echte Backend; Nutzer-Identität konsistent: die Firebase-UID ist die Member-ID in REST, WebSocket und LiveKit.
- Postgres + PostGIS (Supabase) inkl. Schema und Migrationen.
- Live-Karte (MapLibre) mit nummerierten Positionen + Grün/Gelb/Rot-Abstand, Leader-Route mit Adresssuche, SOS-Button, Schnellaktionen und Tankalarm — auf echtem Android-Gerät verifiziert.
- CI grün: Flutter analyze + 328 Tests, Android-/iOS-Build, Backend-Tests.

**In Arbeit:**
- Live-GPS-Feintest auf mehreren echten Geräten (Karte, Abstandswarnung) gegen das deployte Backend.

**Offen:**
- Push-to-Talk: LiveKit-Server noch nicht angebunden — die Token-Route liefert bis dahin `503`.
- Geräte-Verifikation des nativen PTT-Audios (Wiedergabe, Opus-Interop iOS ↔ Android) — bisher nur kompiliert, nicht auf Geräten getestet.
- iOS-Verteilung: braucht einen bezahlten Apple-Developer-Account (TestFlight / Ad-Hoc). Free-Sideload startet bei dieser framework-schweren App nicht zuverlässig.
- Play-Store-Release: echter Android-Keystore statt Debug-Key.
- Optional: Google-Login-UI, Web-Firebase-App.

## Features

- **Live-Konvoi-Karte** — alle Teilnehmer in Echtzeit auf einer MapLibre-Karte. Updates laufen über WebSocket, nicht über Polling.
- **Abstandswarnung** — fällt jemand zu weit zurück, bekommen Hintermann und Konvoi-Leader eine Push-Notification.
- **Nummerierte Positionen + Farbcode** — jedes Mitglied bekommt seine Konvoi-Position (#1 Leader, #2 …) und einen Grün/Gelb/Rot-Status nach Abstand zum Leader, auf Karte und in der Mitgliederliste.
- **Leader-Route** — der Leader setzt mehrere Ziele per Adresssuche (Nominatim) oder Kartentipp; die Route erscheint live bei allen.
- **SOS-Notfall** — 3 Sekunden halten, die eigene Position geht als rotes NOTFALL-Signal an den ganzen Konvoi. Direkt erreichbar (auch im Driver-Mode).
- **Schnellaktionen** — One-Tap-Status an die Gruppe: Pause, Tankstopp, Bin zurück, Problem.
- **Tankalarm** — persönlicher Tankstand mit Reichweiten-Schätzung, Grün/Gelb/Rot-Warnung und Tankstopp-Broadcast.
- **Push-to-Talk** — WebRTC mit LiveKit-SFU, bedienbar per Touchscreen oder CarPlay-Taste.
- **CarPlay** — Karte und PTT auf dem Fahrzeug-Display, über eine Swift-Bridge an die Dart-Seite angebunden.
- **Konvoi-Lifecycle** — erstellen, per Code beitreten, verlassen. REST-API mit Firebase-ID-Token-Auth.
- **Fahrzeugprofile** — mehrere Fahrzeuge pro Nutzer; das aktive Profil bestimmt Standard-Abstand und Karten-Avatar.
- **Backend** — Fastify mit Drizzle/PostGIS für Geo-Queries, Redis-Fanout für horizontal skalierbare WebSockets.
- **Datenschutz (GDPR)** — Analytics & Crash-Reporting (Firebase, Sentry, PostHog) sind Opt-in: standardmäßig aus, per einmaligem Consent-Screen freigeschaltet, jederzeit in der Datenschutz-Seite umschaltbar.

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

Die Authentifizierung läuft über Firebase: die App sendet das Firebase-ID-Token, das Backend verifiziert es gegen Googles öffentliche Schlüssel und nutzt die Firebase-UID als stabile, plattformübergreifende Nutzer- und Member-Identität.

Konventionen im Repo: REST und Realtime liegen in getrennten Layern, GPS-Updates fließen ausschließlich über WebSocket, die Flutter-Seite ist feature-first unter `app/lib/features/` organisiert, und Tests entstehen vor dem Produktionscode.

## Plattform-Status

| Plattform | Stand |
|-----------|-------|
| iOS       | Build grün; Verteilung braucht bezahlten Apple-Account (TestFlight) |
| Android   | Build grün; Login + Konvoi/GPS ans Live-Backend angebunden; Play-Listing offen |
| CarPlay   | Bridge implementiert; Apple-Approval offen |
| Web       | Demo-Preview über `main_web_preview.dart` mit Mock-Backend |
| Backend   | Live auf Render; Postgres+PostGIS (Supabase); Firebase-Token-Auth verifiziert |

## Dev-Sideload ohne bezahlten Apple-Account

Der Workflow `.github/workflows/altstore-ipa.yml` baut auf Knopfdruck eine unsignierte IPA, die sich per [AltStore](https://altstore.io) mit einer kostenlosen Apple-ID aufs eigene iPhone sideloaden lässt. Er strippt dafür Free-Tier-inkompatible Entitlements, entfernt die CarPlay-Scene aus der Info.plist und schreibt die Bundle-ID auf `de.crewlink.app.altstore` um.

Wichtig: Crew Link bindet viele native Frameworks ein (Firebase, WebRTC/LiveKit, MapLibre). Auf manchen Geräten beendet iOS eine mit kostenloser Apple-ID signierte App direkt beim Start, ohne Crash-Log. Zuverlässig läuft iOS erst mit einem bezahlten Apple-Developer-Account. Zum reinen Durchklicken der UI eignet sich der Demo-Build (`lib/main_web_preview.dart`, gemockt) — auch als Android-APK.

## Setup & Konfiguration

| Bereich | Stand / Einrichtung |
|---------|---------------------|
| Firebase | Konfiguriert (Projekt `crew-link-3c852`); E-Mail/Passwort-Login aktiv. Apple-/Google-Login optional, brauchen weitere Einrichtung. |
| Backend-Deploy | Anleitung in [BACKEND_DEPLOY.md](BACKEND_DEPLOY.md): Supabase (Postgres+PostGIS) + Render (Server). Env-Vars: `DATABASE_URL`, `FIREBASE_PROJECT_ID`; optional `REDIS_URL`, `LIVEKIT_*`. |
| App → Backend | Server-URL via `--dart-define=CREW_LINK_API_URL=…`/`CREW_LINK_WS_URL=…` (der Android-APK-Workflow nimmt `api_url`/`ws_url` als Eingaben). Ohne Define: localhost. |
| Push-to-Talk | LiveKit (z. B. LiveKit Cloud) anbinden: `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`. Noch offen. |
| Android-Release-Signing | Für den AAB-Workflow als GitHub-Secrets: `RELEASE_KEYSTORE_BASE64`, `RELEASE_STORE_PASSWORD`, `RELEASE_KEY_ALIAS`, `RELEASE_KEY_PASSWORD` (optional `PLAY_SERVICE_ACCOUNT_JSON` für Auto-Upload). Ohne sie Fallback auf Debug-Key (nicht Play-tauglich). |
| iOS-Signing | `DEVELOPMENT_TEAM` + Apple-Secrets für TestFlight (siehe [TESTFLIGHT.md](TESTFLIGHT.md)). |

## Release-Pipeline

| Workflow | Trigger | Ergebnis |
|----------|---------|----------|
| CI | jeder Push | Flutter- und Backend-Tests, iOS-/Android-Builds |
| Android APK | manuell | installierbare APK als Artifact (mit optionaler Backend-URL) |
| Android AAB (Play) | manuell | Play-signiertes App Bundle (.aab) als Artifact + optionaler Upload in den Play-Internal-Track |
| TestFlight | manuell oder wöchentlich | signierte IPA → App Store Connect |
| AltStore IPA | manuell | unsignierte IPA als Artifact |

## Tech-Stack

- **Mobile:** Flutter 3.41, Dart 3.11, Riverpod, Freezed, go_router, MapLibre, Firebase (Auth, Crashlytics, FCM), LiveKit, WebRTC, Sentry
- **Nativ:** Swift (CarPlay-Bridge), Kotlin
- **Backend:** Node.js, Fastify, TypeScript, Drizzle ORM, jose (Firebase-Token-Verifizierung), Pino, Vitest
- **Daten & Infra:** PostgreSQL mit PostGIS (Supabase), Redis, Docker, Render
- **Release:** Fastlane, GitHub Actions

## Lizenz

Proprietär, © 2026 Crew Link. Der Code ist öffentlich einsehbar, aber nicht zur kommerziellen Wiederverwertung freigegeben.
