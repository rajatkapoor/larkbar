#!/bin/bash
# Builds a LarkBar release: LarkBar-<version>.dmg and .zip in build/release/<version>/.
#
#   scripts/release.sh                 Developer ID signed + notarized (maintainers)
#   scripts/release.sh --skip-notarize Developer ID signed, not notarized
#   scripts/release.sh --unsigned      ad-hoc signed, for building it yourself (no Apple account)
#   scripts/release.sh --publish       also create the GitHub release v<version> with gh
#
# Environment:
#   LARKBAR_SIGNING_IDENTITY  SHA-1 or name of the "Developer ID Application" certificate to use.
#                             Required when the keychain holds more than one.
#   LARKBAR_NOTARY_PROFILE    notarytool keychain profile (default: larkbar-notary). Create it once:
#                             xcrun notarytool store-credentials larkbar-notary \
#                               --apple-id you@example.com --team-id TEAMID --password <app-specific>
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SIGN=1
NOTARIZE=1
PUBLISH=0
for arg in "$@"; do
  case "$arg" in
    --unsigned) SIGN=0; NOTARIZE=0 ;;
    --skip-notarize) NOTARIZE=0 ;;
    --publish) PUBLISH=1 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

fail() { echo "error: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }

NOTARY_PROFILE="${LARKBAR_NOTARY_PROFILE:-larkbar-notary}"
VERSION="$(sed -nE 's/^ *MARKETING_VERSION: *"?([^"]+)"?$/\1/p' project.yml | head -1)"
[ -n "$VERSION" ] || fail "Couldn't read MARKETING_VERSION from project.yml"

OUT="$ROOT/build/release/$VERSION"
ARCHIVE="$OUT/LarkBar.xcarchive"
APP="$OUT/LarkBar.app"
ZIP="$OUT/LarkBar-$VERSION.zip"
DMG="$OUT/LarkBar-$VERSION.dmg"

if [ "${ALLOW_DIRTY:-0}" != "1" ] && [ -n "$(git status --porcelain)" ]; then
  fail "Uncommitted changes. Commit first, or set ALLOW_DIRTY=1."
fi

# --- Signing identity -------------------------------------------------------------------------
SIGN_ARGS=()
if [ "$SIGN" = 1 ]; then
  IDENTITIES="$(security find-identity -v -p codesigning | grep '"Developer ID Application:' || true)"
  if [ -n "${LARKBAR_SIGNING_IDENTITY:-}" ]; then
    IDENTITIES="$(printf '%s\n' "$IDENTITIES" | grep -F "$LARKBAR_SIGNING_IDENTITY" || true)"
  fi
  COUNT="$(printf '%s' "$IDENTITIES" | grep -c . || true)"
  [ "$COUNT" -ge 1 ] || fail "No Developer ID Application certificate found. Use --unsigned to build without one."
  if [ "$COUNT" -gt 1 ]; then
    printf '%s\n' "$IDENTITIES" >&2
    fail "Several Developer ID certificates match. Set LARKBAR_SIGNING_IDENTITY to one SHA-1."
  fi
  IDENTITY_SHA="$(printf '%s\n' "$IDENTITIES" | awk '{print $2}')"
  IDENTITY_NAME="$(printf '%s\n' "$IDENTITIES" | sed -E 's/.*"(.*)"/\1/')"
  TEAM_ID="$(printf '%s\n' "$IDENTITY_NAME" | sed -nE 's/.*\(([A-Z0-9]{10})\)$/\1/p')"
  SIGN_ARGS=("CODE_SIGN_IDENTITY=$IDENTITY_SHA" "DEVELOPMENT_TEAM=$TEAM_ID" "CODE_SIGN_STYLE=Manual"
             "OTHER_CODE_SIGN_FLAGS=--timestamp")
  echo "Signing with: $IDENTITY_NAME ($IDENTITY_SHA)"
fi

if [ "$NOTARIZE" = 1 ]; then
  NOTARY_LOG="$(mktemp -t larkbar-notary)"
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>"$NOTARY_LOG" || {
    cat "$NOTARY_LOG" >&2
    fail "Notary profile '$NOTARY_PROFILE' isn't usable. Fix it, or pass --skip-notarize."
  }
fi

# --- Build ------------------------------------------------------------------------------------
rm -rf "$OUT"
mkdir -p "$OUT"

step "Generating the Xcode project"
if command -v xcodegen >/dev/null; then xcodegen generate --quiet; else echo "xcodegen not installed; using the committed project"; fi

step "Running tests"
xcodebuild -project LarkBar.xcodeproj -scheme LarkBar -configuration Debug \
  -derivedDataPath build/DerivedData test -quiet

step "Archiving LarkBar $VERSION"
xcodebuild -project LarkBar.xcodeproj -scheme LarkBar -configuration Release \
  -destination "generic/platform=macOS" -archivePath "$ARCHIVE" \
  ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} archive -quiet
ditto "$ARCHIVE/Products/Applications/LarkBar.app" "$APP"

if [ "$SIGN" = 1 ]; then
  step "Verifying the Developer ID signature"
  codesign --verify --deep --strict --verbose=2 "$APP"
  codesign -dvv "$APP" 2>&1 | grep -E "Authority=Developer ID Application|flags=.*runtime" >/dev/null \
    || fail "App isn't signed with Developer ID and the hardened runtime."
fi

notarize() {
  local file="$1" result="$OUT/notary-$(basename "$1").plist"
  xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --wait --output-format plist >"$result"
  local status id
  status="$(/usr/libexec/PlistBuddy -c 'Print :status' "$result")"
  id="$(/usr/libexec/PlistBuddy -c 'Print :id' "$result")"
  if [ "$status" != "Accepted" ]; then
    xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" >&2 || true
    fail "Notarization of $(basename "$file") returned $status"
  fi
}

if [ "$NOTARIZE" = 1 ]; then
  step "Notarizing the app"
  ditto -c -k --keepParent "$APP" "$OUT/notary-upload.zip"
  notarize "$OUT/notary-upload.zip"
  rm "$OUT/notary-upload.zip"
  xcrun stapler staple "$APP"
fi

# --- Package ----------------------------------------------------------------------------------
step "Packaging"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

STAGING="$OUT/dmg"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/LarkBar.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "LarkBar $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGING"

if [ "$SIGN" = 1 ]; then
  codesign --sign "$IDENTITY_SHA" --timestamp "$DMG"
fi
if [ "$NOTARIZE" = 1 ]; then
  step "Notarizing the disk image"
  notarize "$DMG"
  xcrun stapler staple "$DMG"
  spctl --assess --type execute --verbose "$APP"
fi

(cd "$OUT" && shasum -a 256 "$(basename "$DMG")" "$(basename "$ZIP")" > SHA256SUMS.txt)

echo
echo "Release $VERSION ready in $OUT:"
ls -1 "$OUT" | grep -E '\.(dmg|zip|txt)$' | sed 's/^/  /'
[ "$SIGN" = 1 ] || echo "  (ad-hoc signed: macOS will ask you to approve it in Privacy & Security on first launch)"
[ "$SIGN" = 0 ] || [ "$NOTARIZE" = 1 ] || echo "  (not notarized: first launch needs Open Anyway in Privacy & Security)"

# --- Publish ----------------------------------------------------------------------------------
if [ "$PUBLISH" = 1 ]; then
  step "Publishing v$VERSION on GitHub"
  NOTES="$ROOT/release-notes/$VERSION.md"
  [ -f "$NOTES" ] || fail "Write the release notes in $NOTES first."
  git push origin HEAD
  if gh release view "v$VERSION" >/dev/null 2>&1; then
    gh release upload "v$VERSION" "$DMG" "$ZIP" "$OUT/SHA256SUMS.txt" --clobber
  else
    gh release create "v$VERSION" "$DMG" "$ZIP" "$OUT/SHA256SUMS.txt" \
      --title "LarkBar $VERSION" --notes-file "$NOTES" --target "$(git rev-parse HEAD)"
  fi
fi
