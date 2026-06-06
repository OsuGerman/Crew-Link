# Play-Store-Release – Checkliste

Schnellster Weg zu einem ersten Release: **Internal Testing Track** (kein Google-Review,
Tester per E-Mail einladen, in Minuten live). Production kommt danach mit demselben AAB.

## Schon erledigt (Code-Seite)
- App-Version **1.0.0+1** (`app/pubspec.yaml`), `targetSdk` Play-konform, `allowBackup=false`
- Eigenes Launcher-Icon, Permissions deklariert (Standort, Mikrofon, Benachrichtigungen)
- **GDPR-Consent-Gate** (Analytics/Crash sind Opt-in, Default aus) + Datenschutztext (DE/EN)
- **AAB-Build-Pipeline** (`.github/workflows/android-aab.yml`) — baut ein signiertes App Bundle,
  sobald die Keystore-Secrets gesetzt sind, optional Auto-Upload in den Internal-Track
- Backend live auf Render

## Was DU machen musst

### 1. Google-Play-Console-Konto (einmalig 25 $)
[play.google.com/console](https://play.google.com/console) → registrieren (Entwicklerkonto).

### 2. Upload-Keystore erzeugen (einmalig, sicher aufbewahren!)
```powershell
keytool -genkey -v -keystore crewlink-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias crewlink
# Passwörter merken! Dann base64 für den CI-Secret:
[Convert]::ToBase64String([IO.File]::ReadAllBytes("crewlink-upload.jks")) | Out-File keystore.b64.txt
```
⚠️ Den `.jks` + die Passwörter sicher sichern — geht er verloren, kannst du keine Updates mehr signieren.

### 3. GitHub-Secrets setzen
Repo → **Settings → Secrets and variables → Actions → New repository secret**:
| Secret | Wert |
|---|---|
| `RELEASE_KEYSTORE_BASE64` | Inhalt von `keystore.b64.txt` |
| `RELEASE_STORE_PASSWORD` | Keystore-Passwort |
| `RELEASE_KEY_ALIAS` | `crewlink` |
| `RELEASE_KEY_PASSWORD` | Key-Passwort |

### 4. Signiertes AAB bauen
GitHub → **Actions → "Android AAB (Play)" → Run workflow** (mit deiner Backend-URL).
Danach das `CrewLink-AAB-*`-Artifact herunterladen → `app-release.aab`.

### 5. Datenschutz-URL hosten (Play-Pflicht)
Repo → **Settings → Pages → Source: `main` / `/docs`** → speichern.
URL wird dann z. B. `https://osugerman.github.io/Crew-Link/privacy.html`.

### 6. In der Play Console
- **App erstellen**: Name „Crew Link", Deutsch, App (nicht Spiel), kostenlos.
- **Store-Eintrag** (Entwurf siehe unten) + Grafiken (Icon 512×512, Feature-Grafik 1024×500, ≥2 Phone-Screenshots).
- **Data Safety** (Mapping unten ausfüllen).
- **Content-Rating**-Fragebogen.
- **Datenschutzerklärung**: die URL aus Schritt 5.
- **App-Zugriff**: „Alle Funktionen brauchen Login" → Test-Account angeben (für den Review).
- **Internes Testing → Release erstellen** → AAB hochladen → Tester (E-Mail) einladen.
  Beim ersten Upload bietet Google **Play App Signing** an → annehmen (dein Keystore = Upload-Key).

## Store-Eintrag (Entwurf)
- **Titel:** Crew Link
- **Kurzbeschreibung (max 80):** Live-Konvoi-Koordination: Karte, Abstandswarnung, Push-to-Talk.
- **Vollständige Beschreibung:**
  > Crew Link hält Fahrzeuggruppen auf gemeinsamen Touren zusammen. Jeder sieht den
  > Konvoi live auf der Karte, mit nummerierten Positionen und Grün/Gelb/Rot-
  > Abstandswarnung. Der Leader legt eine Route mit mehreren Zielen fest, per
  > Adresssuche. Push-to-Talk-Funk, SOS-Notfallsignal, Schnellaktionen (Pause/
  > Tankstopp) und ein Tankalarm runden die Fahrt ab. Diagnose-Daten nur mit
  > deiner Zustimmung.

## Data-Safety-Mapping (Play-Formular)
| Datentyp | Erhoben | Geteilt | Zweck | Hinweis |
|---|---|---|---|---|
| Genauer Standort | Ja | Mit Konvoi-Mitgliedern (Echtzeit) | App-Funktion | Nicht dauerhaft gespeichert |
| Audio (Mikrofon) | Ja | Mit Konvoi-Mitgliedern (Stream) | App-Funktion | Nicht aufgezeichnet |
| E-Mail-Adresse | Ja | Nein | Konto/Anmeldung | Firebase Auth |
| App-Aktivität (Nutzung) | Optional | Nein | Analyse | Opt-in (Firebase Analytics, PostHog) |
| Absturzdaten | Optional | Nein | Diagnose/App-Funktion | Opt-in (Crashlytics, Sentry) |
| Geräte-ID (Push-Token) | Ja | Nein | Benachrichtigungen | FCM |

- Daten bei Übertragung verschlüsselt: **Ja**
- Nutzer kann Löschung anfordern: **Ja**

## Screenshots
Aus den Tests liegen schon welche bereit (Consent-Screen, Active-View mit Karte, Lobby).
Für den Eintrag brauchst du ≥2 saubere Phone-Screenshots (am besten frisch im laufenden Konvoi).
