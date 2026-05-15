# Crew Link — Release-Health-Dashboard

Owner: adrian.mirwaldt21@gmail.com
Target: 99.5% crash-free sessions in production (see project goal).

## Data sources

| Signal | Source | Notes |
| --- | --- | --- |
| Crash-free sessions | Firebase Crashlytics (project `crew-link-prod`) | Native iOS + Android |
| Dart/Flutter uncaught errors | Sentry project `crew-link-mobile` | `release = crew_link@<semver>+<build>`, `environment = prod\|staging\|dev` |
| ANRs / app hangs | Crashlytics → Performance | Track P95 frame time |
| GPS stream drop rate | Backend logs → `convoys_realtime_drop_total` | Stream gateway metric |

## Dashboard tiles

1. **Crash-free sessions (24h, 7d)** — Crashlytics line chart, goal line at 99.5%.
2. **Top 5 crash signatures (last release)** — Crashlytics issues sorted by impact.
3. **Sentry release adoption** — % of sessions on latest release vs. previous two.
4. **Fatal Dart errors per session** — Sentry, grouped by `release`.
5. **Convoy join → first GPS within 30s** — funnel from backend events.
6. **Push-to-talk latency P95** — RTC stats fed into Sentry transactions.

## Alerting

| Condition | Channel | Threshold |
| --- | --- | --- |
| Crash-free sessions < 99% over 1h | Slack `#crew-link-oncall` | Page on call |
| New crash signature with >50 sessions in 30 min | Slack + email | Investigate same release window |
| Sentry release adoption < 60% after 48h | Email | Re-issue TestFlight invite |

## Release gating checklist

- [ ] `flutter analyze` clean on the release branch
- [ ] `flutter test` green on the release branch
- [ ] TestFlight build distributed to internal testers >=24h before App Store submit
- [ ] Crashlytics + Sentry confirm <0.5% crash rate during TestFlight window
- [ ] Dashboard URL pasted into the release ticket

## Environment wiring

Builds inject the DSN and release via Dart defines:

```
flutter build ipa \
  --dart-define=SENTRY_DSN=$SENTRY_DSN \
  --dart-define=CREW_LINK_RELEASE=crew_link@$VERSION+$BUILD \
  --dart-define=CREW_LINK_ENV=prod
```

If `SENTRY_DSN` is empty the app falls back to Crashlytics only — never crashes
the boot path on bad config (see `ObservabilityBootstrap.build`).
