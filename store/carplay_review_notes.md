# CarPlay Review Notes – Crew Link

## Entitlements

The app uses three CarPlay entitlements (all require explicit Apple approval):

| Entitlement | Purpose | Approval status |
|---|---|---|
| `com.apple.developer.carplay-maps` | CPMapTemplate / Navigation category | Pending |
| `com.apple.developer.carplay-audio` | Audio source integration | Pending |
| `com.apple.developer.carplay-communication` | PTT / VoIP communication button | Pending |

Request URL: https://developer.apple.com/contact/carplay/
Status: **pending approval** (submitted 2026-05-14).

## CarPlay Template

- Scene class: `CPTemplateApplicationScene`
- Root template: `CPMapTemplate` with `CPBarButton` for PTT and a status label

No audio session is opened until the user explicitly taps PTT; background location
is used solely for updating the map pin of the active convoy member.

## Reviewer Checklist

- [ ] CarPlay entitlements approved by Apple (carplay-maps, carplay-audio, carplay-communication)
- [ ] `Runner.entitlements` contains all three CarPlay keys (already set)
- [ ] Provisioning profile regenerated in Developer Portal after approval
- [ ] `bundle exec fastlane sync_signing` re-run to pull updated profile
- [ ] CarPlay UI tested on physical device (Xcode CarPlay simulator acceptable for
      basic flow, but audio requires real device)
- [ ] `PrivacyInfo.xcprivacy` complete: UserDefaults, FileTimestamp, SystemBootTime, DiskSpace (done)
- [ ] `ITSAppUsesNonExemptEncryption = false` present in Info.plist (done)
- [ ] Screenshots uploaded via `bundle exec fastlane upload_metadata`
- [ ] `bundle exec fastlane release` succeeds locally on macOS before CI run

## App Review Notes for Apple

Include verbatim in the "Notes for App Review" field in App Store Connect:

> Crew Link is a real-time convoy coordination app for motorcyclists. CarPlay
> integration displays the live convoy map and a Push-to-Talk button on the
> in-car screen so the rider does not need to touch the iPhone while riding.
>
> The CarPlay navigation entitlement (com.apple.developer.carplay-maps) was
> requested via the CarPlay entitlement form. The app uses CPTemplateApplicationScene
> with CPMapTemplate. No driving instructions or turn-by-turn navigation are
> provided; the map shows convoy member positions only.
>
> To reproduce the CarPlay flow in Simulator:
> 1. Launch app → complete onboarding → tap "Konvoi erstellen"
> 2. Connect CarPlay Simulator via Xcode → Window → CarPlay
> 3. The convoy map and PTT button appear on the CarPlay screen
>
> A demo account is not required – the onboarding can be skipped via the
> "Überspringen" button.

## Screenshot Devices Required by App Store

| Slot        | Device                   | Resolution  |
|-------------|--------------------------|-------------|
| iPhone 6.9" | iPhone 16 Pro Max        | 1320 × 2868 |
| iPhone 6.5" | iPhone 12 Pro Max        | 1284 × 2778 |
| iPhone 5.5" | iPhone 8 Plus            | 1242 × 2208 |
| iPad 13"    | iPad Pro 13" (M4)        | 2064 × 2752 |
| iPad 12.9"  | iPad Pro 12.9" (6th gen) | 2048 × 2732 |

Minimum required: 6.9" + 6.5" slots. 5.5" and iPad are optional but recommended.
Screenshots are captured automatically via `fastlane screenshots` lane.

## Fastlane Lanes

```bash
# Upload metadata + screenshots only (no submission)
bundle exec fastlane upload_metadata

# Submit current App Store version for review (binary already in App Store Connect)
bundle exec fastlane submit_for_review

# Full release: build IPA + upload metadata + submit for review
bundle exec fastlane release BUILD_NAME=1.0.0 BUILD_NUMBER=42
```
