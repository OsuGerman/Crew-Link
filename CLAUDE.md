# Crew Link — Projektregeln für Claude

## Observability

Bei neuen Error-Handler-Ergänzungen (`try/catch`, Stream-`.handleError`, `PlatformDispatcher.onError`)
immer beide Calls einbauen:

```dart
appLog.e('Kontext', error: error, stackTrace: stack);
ObservabilityBootstrap.build().reportError(error, stack);
```

Reine UI-Fehler (z. B. `FlutterError` bei fehlenden Widgets im Test) sind davon ausgenommen.

## Backend (Node.js / TypeScript)

Bei neuen Error-Handler-Ergänzungen (`try/catch`, `.on('error')`, `process.on`) immer den Fastify-/Pino-Logger verwenden — **kein `console.error()`**:

```typescript
// in Route-Handlern / Plugins: request.log oder app.log
log.error({ err }, 'Kontext');

// in process.on / Top-Level-Catch (kein request-scope):
app.log.error({ err }, 'Kontext');
process.exit(1); // nur wenn wirklich fatal
```

Hinweis: Es gibt aktuell keinen Crash-Reporter im Backend. Sobald einer (z. B. Sentry) eingebunden wird, hier ebenfalls beide Calls eintragen (analog zur Flutter-Regel oben).

## Allgemein

- Kein `print()` / `debugPrint()` — ausschließlich `appLog.*` aus `core/observability/app_logger.dart`.
- Jede neue Feature-Datei braucht einen Widget- oder Unit-Test bevor sie gemergt wird.
- `firebase_options.dart` und `GoogleService-Info.plist` enthalten Platzhalter — echte Credentials via `flutterfire configure --project=crew-link` einspielen bevor ein Firebase-Feature getestet wird.
