# Datenschutzerklärung – Crew Link

Stand: 2026-05-14

## Verantwortlicher

Adrian Mirwaldt, adrian.mirwaldt21@gmail.com

## Welche Daten wir erheben

| Datenkategorie | Zweck | Speicherdauer |
|----------------|-------|---------------|
| Präziser GPS-Standort | Live-Positionsübertragung im aktiven Konvoi | Nur während aktiver Konvoi-Session; nicht dauerhaft gespeichert |
| Audio (Mikrofon) | Push-to-Talk-Sprachübertragung | Nicht gespeichert; Stream-only |
| Apple User ID (anonymisiert) | Konvoi-Mitgliedschaft, Anti-Impersonation | Bis zur Account-Löschung |
| Fahrzeugprofil (Modell, Baujahr, Mods) | Anzeige im Konvoi für andere Mitglieder | Bis zur manuellen Löschung durch den Nutzer |

## Was wir NICHT erheben

- Keine Werbung und kein Werbe-Tracking, keine Werbe-Identifier
- Keine Weitergabe an Dritte zu deren eigenen Zwecken
- Keine Weitergabe in Drittländer außerhalb des EWR (Firebase-Region: europe-west1)

## Fehlerberichte & Nutzungsanalyse

Zur Stabilität und Verbesserung der App setzen wir ein:

- **Sentry** und **Firebase Crashlytics** — anonymisierte Absturz- und Fehlerberichte (ohne Klarnamen/E-Mail; `sendDefaultPii` ist deaktiviert).
- **Firebase Analytics** und **PostHog** — pseudonyme Nutzungsstatistiken (welche Funktionen genutzt werden), ohne Werbe-IDs und ohne app-übergreifendes Tracking.

Es werden keine Profile zu Werbezwecken gebildet. Auf Anfrage löschen wir deine zugehörigen Daten (Kontakt unten).

Diese Diagnose- und Analyse-Funktionen sind **standardmäßig deaktiviert** und werden erst nach deiner ausdrücklichen Einwilligung (Opt-in beim ersten Start) aktiviert. Du kannst die Einwilligung jederzeit in der App unter „Datenschutz" widerrufen.

## Standortdaten – Details

Standortdaten werden ausschließlich in Echtzeit an Konvoi-Mitglieder übertragen, denen du aktiv beigetreten bist. Sie werden nicht protokolliert, nicht gespeichert und nicht an Dritte weitergegeben. Hintergrund-Standort wird nur während einer aktiven Konvoi-Session genutzt.

## Mikrofon – Details

Das Mikrofon wird ausschließlich für Push-to-Talk aktiviert, solange du die PTT-Taste hältst. Audiostreams werden nicht aufgezeichnet.

## Betroffenenrechte (DSGVO Art. 15–22)

Du hast das Recht auf Auskunft, Berichtigung, Löschung und Datenübertragbarkeit. Kontakt: adrian.mirwaldt21@gmail.com

## Cookies / lokaler Speicher

Die App speichert ausschließlich App-Einstellungen (z. B. Onboarding-Status) lokal über NSUserDefaults. Es werden keine Cookies gesetzt.

## Änderungen

Änderungen dieser Erklärung werden in der App und unter `https://crewlink.app/privacy` veröffentlicht. Das Datum der letzten Änderung steht oben.
