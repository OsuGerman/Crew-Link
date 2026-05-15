# Crew Link — TestFlight-Bereitstellung

Step-by-Step-Anleitung um die App auf TestFlight zu pushen. Geht davon
aus dass du Owner-Zugriff zum Apple-Developer-Account
`adrian.mirwaldt21@gmail.com` hast und das GitHub-Repo
`OsuGerman/Crew-Link` kontrollierst.

Reihenfolge der Abschnitte spiegelt den natürlichen Onboarding-Pfad —
einmal komplett durch, danach reichen `git push` oder ein manueller
GitHub-Action-Trigger für jeden weiteren Beta-Build.

---

## 0 · Voraussetzungen

| Item | Wie prüfen / besorgen |
|---|---|
| **Apple-Developer-Program-Mitgliedschaft** (99 €/Jahr) | https://developer.apple.com/programs/ |
| **App Store Connect Admin/Account-Holder** | https://appstoreconnect.apple.com/ |
| **Team-ID** (10-stellig) | Apple-Developer-Account → Membership |
| **ITC-Team-ID** (numerisch) | App Store Connect → Users and Access → URL `?providerId=…` |

---

## 1 · App im App Store Connect anlegen

1. https://appstoreconnect.apple.com/apps → **+** → **New App**
2. **Bundle ID**: `de.crewlink.app`
   - Vorher anlegen unter https://developer.apple.com/account/resources/identifiers/list (falls noch nicht da)
   - Capabilities aktivieren: **Sign in with Apple**, **Push Notifications**, **App Groups** (`group.de.crewlink.app`)
   - **CarPlay** Capability wird erst aktiviert nach Approval (siehe Abschnitt 7)
3. **SKU**: `crew-link-ios-001` (frei wählbar)
4. **Primary Language**: Deutsch (DE)
5. **Platform**: iOS

---

## 2 · App Store Connect API-Key (für CI-Auth)

Wird vom Fastlane statt Passwort-Login genutzt — robust + 2FA-frei.

1. App Store Connect → **Users and Access** → **Integrations** → **App Store Connect API**
2. **+** → Name: `crew-link-ci`, Access: **App Manager**
3. **Issuer ID** + **Key ID** kopieren
4. **Download API Key** (`.p8`-Datei) — nur einmal verfügbar!
5. **Base64-Codieren**:
   ```bash
   base64 -i AuthKey_XXXXXXXX.p8 | pbcopy   # macOS, kopiert in Clipboard
   ```
6. GitHub-Repo → **Settings → Secrets and variables → Actions** → diese Secrets anlegen:

   | Secret-Name | Wert |
   |---|---|
   | `ASC_KEY_ID` | Key ID aus Schritt 3 (z.B. `ABC123XYZ`) |
   | `ASC_ISSUER_ID` | Issuer ID aus Schritt 3 |
   | `ASC_KEY_CONTENT` | Base64-Output aus Schritt 5 |
   | `ITC_TEAM_ID` | numerische ITC-Team-ID |
   | `TEAM_ID` | 10-stellige Developer-Team-ID |

---

## 3 · Match-Repo für Signing-Certs (fastlane match)

Match hält Cert + Provisioning-Profile in einem PRIVATEN Git-Repo
verschlüsselt vor. Empfohlen: separates Repo, nur du hast Zugriff.

1. Neues **privates** GitHub-Repo: `crew-link-certs` (oder ähnlich)
2. **Deploy-Key** mit Read+Write-Access dafür anlegen (analog zum
   Main-Repo) — `ssh-keygen -t ed25519 -f ~/.ssh/crewlink_match`
3. Lokal in einem Mac mit Xcode (kein CI):
   ```bash
   cd Crew\ Link
   bundle install
   export MATCH_GIT_URL=git@github.com:OsuGerman/crew-link-certs.git
   export MATCH_PASSWORD='waehl-ein-starkes-passwort'
   bundle exec fastlane sync_signing
   ```
   Beim ersten Lauf erzeugt Match Distribution-Cert + Provisioning-Profile
   und speichert beides verschlüsselt im Certs-Repo.
4. Diese Secrets in GitHub-Repo (Main, nicht Certs!) ergänzen:

   | Secret-Name | Wert |
   |---|---|
   | `MATCH_GIT_URL` | `git@github.com:OsuGerman/crew-link-certs.git` |
   | `MATCH_PASSWORD` | das Passwort von Schritt 3 |

5. Match-Deploy-Key der CI verfügbar machen: Repo → Settings → Secrets →
   **`MATCH_SSH_KEY`** (Inhalt vom privaten `crewlink_match`-Key)
   — TODO: workflow noch nicht so verdrahtet; aktuell muss CI-Maschine
   den Key bekommen. Workaround: HTTPS-Match-URL + Personal Access
   Token statt SSH.

---

## 4 · Xcode-Project final konfigurieren

> Diese Schritte erfordern **macOS + Xcode**. Cloud-Buildservices wie
> Codemagic können das umgehen — aber für CarPlay-Tests brauchst du
> sowieso einen Mac.

Im Xcode:

1. `app/ios/Runner.xcworkspace` öffnen
2. **Runner-Target** → **Signing & Capabilities**:
   - **Team**: dein Apple-Developer-Team auswählen
   - **Bundle Identifier**: `de.crewlink.app` (sollte schon stimmen)
   - **Automatically manage signing**: AUS (match übernimmt das)
   - **Provisioning Profile**: `match AppStore de.crewlink.app`
3. **Capabilities** (mit + Button hinzufügen):
   - ✅ **Sign in with Apple** — Entitlement steht schon in
     `Runner.entitlements`
   - ✅ **Push Notifications** — Entitlement `aps-environment` steht
     schon drin (production)
   - ✅ **App Groups** — `group.de.crewlink.app` (für CarPlay)
   - ✅ **Background Modes** — Location updates + Audio (steht in
     Info.plist)
   - ⏳ **CarPlay Maps** — Approval nötig (siehe Abschnitt 7)

---

## 5 · Firebase-Konfiguration einspielen

`firebase_options.dart` und `GoogleService-Info.plist` enthalten aktuell
**Platzhalter** (siehe `CLAUDE.md`-Regel).

1. https://console.firebase.google.com/ → Projekt `crew-link` (falls
   noch nicht da: anlegen)
2. iOS-App hinzufügen mit Bundle-ID `de.crewlink.app`
3. **GoogleService-Info.plist** downloaden → `app/ios/Runner/` ersetzen
4. **Authentifizierung** → Sign-in-Anbieter aktivieren: **Apple**
   - Service-ID + Key konfigurieren (Apple-Developer-Account)
5. **Realtime Database** + **Cloud Firestore** beide enablen
6. Auf der Maschine die FlutterFire-CLI laufen lassen um
   `firebase_options.dart` zu regenerieren:
   ```bash
   cd app
   dart pub global activate flutterfire_cli
   flutterfire configure --project=crew-link
   ```
7. **Cloud Messaging-APNs-Key**: Apple-Developer-Account → Keys → 
   **+** → "Apple Push Notifications service" enablen → in Firebase
   unter Project Settings → Cloud Messaging hochladen.

---

## 6 · Erster TestFlight-Upload (lokal)

Wenn du auf einem Mac alles getestet hast und sicher bist:

```bash
cd Crew\ Link
bundle install
export MATCH_GIT_URL=git@github.com:OsuGerman/crew-link-certs.git
export MATCH_PASSWORD='dein-passwort'
export ASC_KEY_ID='ABC123'
export ASC_ISSUER_ID='..'
export ASC_KEY_CONTENT="$(base64 -i AuthKey_XXX.p8)"
export ITC_TEAM_ID='..'
export TEAM_ID='..'
export BUILD_NUMBER=1
export BUILD_NAME='0.1.0'
bundle exec fastlane ios beta
```

Was passiert:
1. `flutter build ios --release --no-codesign` → kompiliert Dart →
   native iOS-Code
2. `match` lädt Distribution-Cert + Provisioning-Profile aus dem
   Certs-Repo
3. `increment_build_number` setzt Build-Nummer (Fastlane fängt bei 1 an
   wenn `BUILD_NUMBER` env nicht gesetzt)
4. `build_app` (gym) signiert + archiviert → erzeugt `CrewLink.ipa`
5. `upload_to_testflight` (pilot) lädt die IPA in App Store Connect,
   wartet **NICHT** auf das Processing (CI-Latenz)
6. **`invite_testers`** (separat als `beta_with_testers` lane) lädt
   die 20 Adressen aus `fastlane/testers.csv` in die Gruppe
   `Interne Beta` ein.

Nach 5-15 Min ist der Build in TestFlight unter **My Apps → Crew Link
→ TestFlight** sichtbar.

---

## 7 · CarPlay-Entitlement-Approval bei Apple

CarPlay-Capability muss **explizit beantragt** werden — Apple
genehmigt das fallweise.

1. https://developer.apple.com/contact/carplay/ → "CarPlay Navigation"
   anklicken
2. Formular ausfüllen:
   - **App Name**: Crew Link
   - **Bundle ID**: `de.crewlink.app`
   - **Category**: Navigation (Konvoi-Koordinator, kein klassisches
     Turn-by-Turn — Apple bewertet das gelegentlich strikt)
   - **Justification**: aus `store/carplay_review_notes.md`
3. Antwort 2-8 Wochen, manchmal Ablehnung mit Begründung — dann mit
   überarbeitetem Pitch erneut einreichen
4. Nach Approval: in Developer-Portal → Identifiers → 
   `de.crewlink.app` die `CarPlay Driving Audio App` /
   `CarPlay Navigation App` Capability aktivieren → Provisioning-
   Profile re-generieren (via match)

**Ohne CarPlay-Approval kannst du trotzdem zur TestFlight-Beta gehen** —
einfach die `com.apple.developer.carplay-*`-Keys temporär aus 
`Runner.entitlements` entfernen. Die Standard-App rendert weiterhin
normal, nur das CarPlay-Display fehlt.

---

## 8 · TestFlight-Build per GitHub Actions auslösen

**Option A — auf jeden push to main automatisch:**
- bereits konfiguriert in `.github/workflows/ci.yml` (job `testflight`)
- läuft sobald `app` + `ios` Jobs grün sind

**Option B — manuell on-demand (empfohlen für Beta-Releases):**
- GitHub-Repo → **Actions** → **CI** workflow
- Rechts oben **Run workflow** → Branch `main`
- Inputs:
  - **Version**: `0.1.0` (oder höher pro Release)
  - **Changelog**: was die Tester wissen sollen ("Bug-fixes, neuer
    Waypoint-Editor, …") — wenn leer wird Git-Log der letzten 15
    Commits verwendet
- **Run workflow** → ~15-25 Min später ist der Build in TestFlight

**Option C — wöchentlich automatisch:**
- Cron-Trigger jeden Montag 06:00 UTC läuft automatisch — bereits
  konfiguriert

---

## 9 · Beta-Tester einladen

Manuell:
1. App Store Connect → My Apps → Crew Link → TestFlight
2. **Internal Testing** → Gruppe `Interne Beta` → **+** → Tester-E-Mails
3. Build auswählen → **Save**

Per Fastlane (aus `fastlane/testers.csv`):
```bash
bundle exec fastlane ios invite_testers
```

Die Tester bekommen eine Einladung von Apple mit Link zur TestFlight-
App und Code zum Beitreten.

---

## 10 · Beta-Test-Notes pro Build

`fastlane/Pilotfile` enthält schon einen Default-Text:
```ruby
localized_build_info({
  "default" => {
    whats_new: "Aktuelle Beta – Feedback bitte via GitHub Issues eintragen."
  }
})
```

Pro Build-Upload überschreibst du das via `workflow_dispatch` Input
**Changelog**.

Für persistente Beta-App-Beschreibung (auf der TestFlight-Seite, NICHT
pro-Build): App Store Connect → TestFlight → Beta App Description.

---

## 11 · Häufige Fehler & Fixes

### "No matching profiles found" beim build_app
→ `match` neu laufen lassen mit `readonly: false`:
```bash
bundle exec fastlane sync_signing
```

### "Invalid Code Signing Entitlements"
→ Wahrscheinlich `com.apple.developer.carplay-maps` ohne Approval.
Temporär die CarPlay-Keys aus `Runner.entitlements` entfernen, neu
matchen, neu builden.

### "ITSAppUsesNonExemptEncryption is true"
→ `Info.plist` hat den Key auf `false`. Wenn du **nicht** Standard-iOS-
Encryption (NSURLSession HTTPS, Sign in with Apple) nutzt, müsstest
du das ändern und ggf. eine Encryption-Export-Declaration einreichen.
Aktueller Stand: nur Standard-Krypto → `false` korrekt.

### "Build still processing" im TestFlight
→ Normal, dauert 5-30 Min. Erst nach Processing-OK können Tester
herunterladen. Wenn der CI-Job grün ist, ist der Upload erfolgreich
gewesen — nur App-Store-seitig läuft die Verarbeitung noch.

### "Sign in with Apple" fehlt im TestFlight-Build
→ Entitlement im File `Runner.entitlements` prüfen (Key
`com.apple.developer.applesignin`), Provisioning-Profile re-matchen.

### CarPlay-Bridge nicht sichtbar im Auto
→ Apple-Developer-Account: CarPlay-Capability MUSS approved sein,
sonst läuft der CPTemplateApplicationScene-Delegate nicht. Sieh in der
Console des verbundenen Macs/Xcode nach den Fehlermeldungen.

---

## 12 · Checkliste vor jedem Beta-Build

- [ ] `git push origin main` ist grün auf Actions
- [ ] `flutter analyze` lokal clean
- [ ] `flutter test` lokal grün (`cd app && flutter test`)
- [ ] Backend-Tests grün (`cd backend && npm test`)
- [ ] `pubspec.yaml` Version ggf. erhöht (Patch oder Minor)
- [ ] Manuell auf echtem iPhone smoketest: Login → Konvoi erstellen →
      andere Person beitreten lassen → PTT testen → Konvoi verlassen
- [ ] `store/carplay_review_notes.md` für aktuelle Release-Notes
      gegengelesen
- [ ] `fastlane/metadata/de-DE/release_notes.txt` ggf. aktualisiert

---

## Anhang · Dateistruktur

```
.github/workflows/
  ci.yml                # 4 Jobs: app, android, ios, testflight + backend
fastlane/
  Fastfile              # Lanes: sync_signing, beta, screenshots, release,
                        #         invite_testers, beta_with_testers, …
  Appfile               # app_identifier, apple_id, *_team_id
  Matchfile             # git_url, storage_mode, type, app_identifier
  Pilotfile             # TestFlight-Defaults (groups, what's-new)
  Gymfile               # workspace, scheme, output_dir
  Deliverfile           # App-Store-Listing-Defaults
  Snapfile              # Screenshot-Devices + Sprachen
  testers.csv           # 20 Beta-Tester-Mails (Demo, austauschen)
  metadata/de-DE/       # App-Store-Listing-Texte (Description, Keywords, …)
  metadata/en-US/       #   dito Englisch
  screenshots/          # generierte Screenshots (Fastlane Snapshot)
app/ios/Runner/
  Info.plist            # Privacy-Strings, Background-Modes,
                        # UIBackgroundModes [location, audio],
                        # ITSAppUsesNonExemptEncryption = false,
                        # CFBundleURLSchemes [crewlink], CarPlay-Scene
  Runner.entitlements   # Release: applesignin + aps-environment=production
                        #          + carplay-* + app-group
  RunnerDebug.entitlements # Debug: aps-environment=development
  PrivacyInfo.xcprivacy # Apple-Privacy-Manifest (Location, Audio, DeviceID)
  CarPlay/              # SceneDelegate + Bridge + Coordinator
store/
  carplay_review_notes.md
  privacy_policy.md     # Verlinkt aus App-Store-Listing (Public-Hosted)
  release_health_dashboard.md
```

---

## Was Claude für diesen Sprint angefasst hat

Sind die 47 Files im Commit `994991c` ("feat: Design-System Pass +
Konvoi-Features #1-#5") — Theme-Migration + 5 neue Features. Der
TestFlight-Anteil davon ist nur:

- `Runner.entitlements` — Sign in with Apple + Push Notifications
  hinzugefügt (waren vorher nur CarPlay)
- `RunnerDebug.entitlements` — neuer File mit
  `aps-environment=development`
- `.github/workflows/ci.yml` — `workflow_dispatch`-Input für
  Version + Changelog
- `fastlane/Fastfile` — beta-Lane respektiert `TF_CHANGELOG` env

Alles andere war schon vor diesem Sprint da (Adrian's Initialaufbau).
