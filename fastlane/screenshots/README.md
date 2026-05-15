# Screenshots – Crew Link

Required screenshot sizes for App Store Connect:

| Device              | Size px        | Slot name                   |
|---------------------|----------------|-----------------------------|
| iPhone 16 Pro Max   | 1320 × 2868    | `iPhone_69`                 |
| iPhone 14 Plus      | 1284 × 2778    | `iPhone_65`                 |
| iPhone SE (3rd)     | 750  × 1334    | `iPhone_55`                 |
| iPad Pro 13" (M4)   | 2064 × 2752    | `iPad_Pro_129`              |

Minimum 1 screenshot per device class required; Apple recommends 5–6.

## Naming convention

`<slot>_<sequence>_<screen-slug>.png`

Example: `iPhone_69_01_live-map.png`

## Screens to capture

1. `live-map`       — Live-Karte mit 3+ Mitgliedern auf der Route
2. `convoy-home`    — Startscreen: Konvoi aktiv, Mitgliederliste
3. `ptt-active`     — Push-to-Talk aktiv (Wellenform sichtbar)
4. `distance-warn`  — Abstandswarnung-Banner
5. `vehicle-profile`— Fahrzeugprofil-Formular ausgefüllt
6. `carplay-screen` — CarPlay-Ansicht mit PTT-Button (Simulator-Screenshot)

## Generating screenshots

Use fastlane snapshot (requires a Mac with Xcode):

    bundle exec fastlane snapshot

Or capture manually via Xcode Simulator → File → Save Screen.

Placeholder graphics: place 1920×1080 PNG files with `_placeholder` suffix;
CI skips placeholder files during deliver.
