#!/usr/bin/env bash
# Upload debug symbols to Crashlytics and Sentry after iOS archive.
#
# Required env vars:
#   SENTRY_AUTH_TOKEN  — from sentry.io → Settings → Auth Tokens
#   SENTRY_ORG         — Sentry org slug
#   GOOGLE_APP_ID      — from GoogleService-Info.plist (GOOGLE_APP_ID field)
#   FIREBASE_CI_TOKEN  — service account JSON path or CI token
#
# Called from Xcode Cloud / CI after the archive step.
set -euo pipefail

DSYM_DIR="${DWARF_DSYM_FOLDER_PATH:-${BUILT_PRODUCTS_DIR}}"

echo "==> Uploading dSYMs to Firebase Crashlytics..."
"${PODS_ROOT}/FirebaseCrashlytics/upload-symbols" \
  -gsp "${SRCROOT}/Runner/GoogleService-Info.plist" \
  -p ios \
  "${DSYM_DIR}"

echo "==> Uploading dSYMs to Sentry..."
sentry-cli \
  --auth-token "${SENTRY_AUTH_TOKEN}" \
  debug-files upload \
  --org "${SENTRY_ORG}" \
  --project crew-link \
  "${DSYM_DIR}"

echo "==> Creating Sentry release ${CREW_LINK_RELEASE:-unknown}..."
sentry-cli \
  --auth-token "${SENTRY_AUTH_TOKEN}" \
  releases \
  --org "${SENTRY_ORG}" \
  --project crew-link \
  new "${CREW_LINK_RELEASE:-crew_link@0.1.0+1}"

sentry-cli \
  --auth-token "${SENTRY_AUTH_TOKEN}" \
  releases \
  --org "${SENTRY_ORG}" \
  --project crew-link \
  finalize "${CREW_LINK_RELEASE:-crew_link@0.1.0+1}"

echo "==> Symbol upload complete."
