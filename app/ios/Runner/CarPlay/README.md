# CarPlay scaffolding

This folder holds the native iOS side of the CarPlay integration.
The Swift files **must be added to the Xcode target manually** the first
time you open the project on a Mac, because `project.pbxproj` was not
edited by the Windows scaffold:

1. Open `ios/Runner.xcworkspace` in Xcode.
2. Right-click the `Runner` group → *Add Files to "Runner"…*.
3. Select the four Swift files in `ios/Runner/CarPlay/` (uncheck
   *Copy items if needed* — they already live in the right place).
4. Confirm "Runner" is the only target checked.

After that, two more Xcode-side configurations:

- **Capabilities → CarPlay**: enable on the Runner target. Xcode will
  add the `com.apple.developer.carplay-maps` key to the entitlements
  file at `ios/Runner/Runner.entitlements` (already scaffolded with the
  right value).
- **Signing & Capabilities**: tick *Automatically manage signing*.
  Without an Apple-issued CarPlay entitlement on the provisioning
  profile, the app will install but CarPlay will not connect. See
  `https://developer.apple.com/contact/carplay/` for the entitlement
  application — this is a paperwork step Apple gates.

To test without a head unit:
- Xcode 13+: *Window → Devices and Simulators*, run on iPhone simulator
  with the *CarPlay* simulator window open in the I/O menu.
- Real CarPlay-equipped car with a paired iPhone running the dev build.

The Swift code is written against iOS 14 APIs (`CPMapTemplate`,
`CPMapButton`, `CPTemplateApplicationSceneDelegate`). Set the iOS
deployment target to at least 14.0 in the Xcode project.

## Files

- `CarPlaySceneDelegate.swift` — owns the CarPlay scene lifecycle
- `CarPlayCoordinator.swift` — owns the `CPMapTemplate` + the PTT button
- `CarPlayBridge.swift` — `FlutterMethodChannel` ↔ CarPlay event router

## Wire format (mirrors `app/lib/core/carplay/carplay_bridge.dart`)

Channel name: `crewlink/carplay`

Native → Dart (`invokeMethod`):
- `pttPressed` — user pressed the in-CarPlay PTT button
- `pttReleased` — user released (currently auto-released after 400 ms;
  see comment in `CarPlayCoordinator.swift`)

Dart → Native (`setMethodCallHandler`):
- `updateConvoyState({ memberCount: Int, proximityActive: Bool })` —
  refresh the map template status bar
