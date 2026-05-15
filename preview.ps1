# Startet die Crew-Link Web-Preview auf http://127.0.0.1:9090
# Ziel: iOS-Bezel (iPhone 16 Pro) im Browser, kein Firebase nötig.
#
# Verwendung:  .\preview.ps1
# Stoppen:     Ctrl+C
#
# WICHTIG: Wir wechseln in die NTFS-Junction C:\dev\crew-link, weil
# der `objective_c` Native-Assets-Build-Hook an Pfaden mit Leerzeichen
# beim `dart compile kernel` scheitert.

$ErrorActionPreference = 'Stop'

$junction = 'C:\dev\crew-link'

if (-not (Test-Path $junction)) {
    Write-Error "Junction $junction fehlt. Anlegen mit: cmd /c mklink /J $junction `"$PSScriptRoot`""
    exit 1
}

$flutterBat = Join-Path $junction 'flutter\bin\flutter.bat'
$appDir     = Join-Path $junction 'app'

if (-not (Test-Path $flutterBat)) {
    Write-Error "Flutter SDK nicht gefunden: $flutterBat"
    exit 1
}

Write-Host "Crew Link Web-Preview" -ForegroundColor Cyan
Write-Host "URL: http://127.0.0.1:9090  (iPhone 16 Pro Bezel)" -ForegroundColor Green
Write-Host "Einstiegspunkt: lib/main_web_preview.dart (kein Firebase)" -ForegroundColor Yellow
Write-Host "Working dir:    $appDir  (junction, ohne Leerzeichen)" -ForegroundColor DarkGray
Write-Host ""

Set-Location $appDir

& $flutterBat run `
    --device-id web-server `
    --web-port 9090 `
    --web-hostname 127.0.0.1 `
    --target lib/main_web_preview.dart
