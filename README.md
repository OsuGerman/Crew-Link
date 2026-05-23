<div align="center">

# 🏍️ Crew Link

**Halte deinen Konvoi zusammen.**

Live-GPS-Karte · Automatische Abstandswarnung · Push-to-Talk · CarPlay-Integration

[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20Android%20%7C%20CarPlay-1a1a1a?style=flat-square)](#-plattformen)
[![Flutter](https://img.shields.io/badge/Flutter-3.22-02569B?style=flat-square&logo=flutter)](https://flutter.dev)
[![Backend](https://img.shields.io/badge/Backend-Fastify%20%2B%20PostGIS-009688?style=flat-square&logo=node.js)](backend/)
[![License](https://img.shields.io/badge/license-proprietary-ff6b35?style=flat-square)](#-lizenz)

[Features](#-features) · [Quickstart](#-quickstart) · [Architektur](#-architektur) · [TestFlight](TESTFLIGHT.md) · [AltStore-Sideload](#-altstore-sideload)

</div>

---

## 🎯 Worum geht's

Crew Link ist ein Konvoi-Koordinator für Fahrzeuggruppen — gedacht für Motorrad-Touren, Roadtrips und Off-Road-Crews, die zusammen unterwegs sind und nicht ständig den Rückspiegel checken wollen, ob der Hintermann noch da ist.

Ein Klick startet einen Konvoi, der Rest der Gruppe joint per Link. Die App zeigt jeden Teilnehmer live auf der Karte, warnt automatisch wenn jemand zurückfällt, und bietet eine Push-to-Talk-Funkverbindung, die auch über CarPlay funktioniert.

---

## ✨ Features

| | |
|---|---|
| 🗺️ **Live-Konvoi-Karte** | Alle Teilnehmer in Echtzeit auf einer MapLibre-Karte. Updates fließen ausschließlich über WebSocket — kein Polling, keine kalten Caches. |
| 🚨 **Abstandswarnung** | Wenn jemand zu weit zurückfällt, bekommen Hintermann und Konvoi-Leader eine Push-Notification — bevor jemand abgehängt wird. |
| 🎙️ **Push-to-Talk** | WebRTC-basiertes Walkie-Talkie mit LiveKit-SFU. Halten → reden → loslassen. Bedienbar über Touchscreen oder CarPlay-Taste. |
| 🚗 **CarPlay-Integration** | Karte und PTT direkt aufs Auto-Display. Eigene Swift-Bridge, die mit Dart über Method-Channels spricht. |
| 🛣️ **Konvoi-Lifecycle** | Konvoi erstellen, per Link/Code beitreten, verlassen — REST-API mit Apple-Sign-In-Token-Bridge zum Realtime-Gateway. |
| 🏍️ **Fahrzeugprofile** | Pro User mehrere Fahrzeuge (Bike/Auto/Van), das aktive Profil bestimmt Default-Abstand und Avatar in der Karte. |
| 📡 **Skalierbares Backend** | Fastify + Drizzle/PostGIS für Geo-Queries, Redis-Fanout für horizontale WebSocket-Skalierung. |
| 🧪 **Test-getrieben** | Widget-Tests, Unit-Tests, Integration-Tests. Jede Feature-Datei kommt mit Test ins Repo. |

---

## 📦 Monorepo-Struktur

```
crew-link/
├── app/                     # Flutter-App (Dart, Riverpod, Freezed, MapLibre)
│   ├── lib/features/        # Feature-First: auth, convoy, maps, push_to_talk, …
│   ├── ios/                 # Native iOS + CarPlay-Bridge (Swift)
│   └── android/             # Native Android
│
├── backend/                 # Fastify + TypeScript
│   └── src/
│       ├── routes/          # REST-API (Konvoi-Lifecycle, Auth)
│       ├── realtime/        # WebSocket-Gateway + Redis-Fanout
│       └── db/              # Drizzle-Schema + PostGIS-Migrations
│
├── infra/                   # docker-compose: Postgres + PostGIS
├── fastlane/                # iOS-Release-Pipeline (TestFlight, App Store)
├── store/                   # App-Store-Texte, CarPlay-Review-Notes
├── docs/                    # Landing-Page (GitHub Pages) + Privacy
└── .github/workflows/       # CI: app · android · ios · backend · testflight · altstore-ipa
```

---

## 🚀 Quickstart

### Flutter-App
```sh
cd app
flutter pub get
flutter analyze
flutter test
flutter run
```

> **Windows-Tipp:** Eine vendored Flutter-SDK liegt unter `flutter/bin/flutter.bat`. Einmal pro Session in PATH legen:
> ```powershell
> $env:PATH = "$PWD\..\flutter\bin;$env:PATH"
> ```

### Backend
```sh
cd backend
npm install
npm test
npm run dev      # startet Fastify mit Hot-Reload
```

### Lokale Postgres + PostGIS
```sh
cd infra
docker compose up -d
cd ../backend
npm run db:generate     # Drizzle-Migration (fixt PostGIS-Identifier-Quoting)
npm run db:migrate
```

---

## 🧱 Architektur

```
       ┌────────────────────┐         ┌────────────────────┐
       │   Flutter App      │         │   CarPlay-Bridge   │
       │   (iOS / Android)  │◄───────►│   (Swift)          │
       └─────────┬──────────┘         └────────────────────┘
                 │
       REST (Auth, Lifecycle)
       WebSocket (GPS-Stream)
       WebRTC (Push-to-Talk)
                 │
       ┌─────────▼──────────┐         ┌────────────────────┐
       │   Fastify Backend  │◄───────►│   Redis (Fanout)   │
       │   (TypeScript)     │         └────────────────────┘
       └─────────┬──────────┘
                 │
       ┌─────────▼──────────┐         ┌────────────────────┐
       │  Postgres+PostGIS  │         │  LiveKit SFU       │
       │  (Geo-Persistence) │         │  (Audio Fan-Out)   │
       └────────────────────┘         └────────────────────┘
```

### Spielregeln
- **REST und Realtime** leben in getrennten Layern (`backend/src/routes/` vs `backend/src/realtime/`).
- **GPS-Updates fließen ausschließlich** über WebSocket — kein REST-Polling.
- **PTT-Audio** läuft über WebRTC + LiveKit-SFU für skalierbares Fan-Out.
- **Persistenz** ist Postgres + PostGIS only.
- **Flutter** folgt einem Feature-First-Layout unter `app/lib/features/`.
- **Endpoints** sind spec-first (OpenAPI/JSON-Schema) vor der Implementierung.
- **TDD**: Tests kommen vor dem Produktionscode — sowohl in `app/` als auch in `backend/`.

---

## 📱 Plattformen

| Plattform | Status | Anmerkung |
|---|---|---|
| **iOS** | ✅ Build grün | TestFlight-Pipeline via Fastlane fertig — siehe [TESTFLIGHT.md](TESTFLIGHT.md) |
| **CarPlay** | ✅ Bridge implementiert | Approval bei Apple offen (Navigation-Category) |
| **Android** | ✅ Build grün | Play-Store-Listing noch nicht aufgebaut |
| **Web** | 🧪 Demo-Preview | `main_web_preview.dart` mit Mock-Backend für UI-Reviews |

---

## 🧪 AltStore-Sideload

Für Dev-Builds ohne bezahltes Apple-Developer-Program: der Workflow [`.github/workflows/altstore-ipa.yml`](.github/workflows/altstore-ipa.yml) baut auf Knopfdruck eine **unsignierte IPA**, die per [AltStore](https://altstore.io) mit einer Free-Apple-ID aufs eigene iPhone gesideloaded werden kann.

So geht's:

1. GitHub → **Actions** → **AltStore IPA** → **Run workflow**
2. Artifact `CrewLink-AltStore-N` runterladen → AltStore-App auf dem iPhone → IPA installieren
3. Profil unter *Settings → General → VPN & Device Management* vertrauen

Was der Workflow automatisch strippt, damit AltStore re-signen kann:
- Free-Tier-inkompatible Entitlements (Sign-In, Push, CarPlay, App-Groups)
- CarPlay-Scene aus der `Info.plist`
- Bundle-ID auf `de.crewlink.app.altstore` umgeschrieben → koexistiert mit späterem TestFlight-Build

---

## 🚢 Release-Pipeline

| Workflow | Trigger | Output |
|---|---|---|
| **CI** | jeder Push | Flutter-Tests, Backend-Tests, iOS-/Android-Builds |
| **TestFlight** | `workflow_dispatch` oder wöchentlich Mo 06:00 UTC | Signierte IPA → App Store Connect → Tester-Gruppe |
| **AltStore IPA** | `workflow_dispatch` | Unsignierte IPA als Artifact (30 Tage Retention) |

Komplette TestFlight-Beta-Anleitung inkl. Fastlane-Setup, Match-Repo und CarPlay-Approval-Prozess: **[TESTFLIGHT.md](TESTFLIGHT.md)**.

---

## 🛠️ Tech-Stack

**Mobile:** Flutter 3.22 · Dart 3.4 · Riverpod · Freezed · go_router · MapLibre · Firebase (Auth, Crashlytics, FCM) · LiveKit · WebRTC · Sentry

**Native:** Swift (CarPlay-Bridge) · Kotlin

**Backend:** Node.js · Fastify · TypeScript · Drizzle ORM · Pino (Logger) · Vitest

**Persistenz & Infra:** PostgreSQL + PostGIS · Redis (Fanout) · Docker Compose

**Release:** Fastlane · GitHub Actions · AltStore (Dev-Sideload)

---

## 📜 Lizenz

Proprietär — © 2026 Crew Link. Code ist öffentlich einsehbar, aber **nicht** zur kommerziellen Wiederverwertung freigegeben. Pull Requests und Issues sind willkommen.

---

<div align="center">

Made with 🏍️ + ☕ — auf Tour bleiben, nicht zurückgelassen werden.

</div>
