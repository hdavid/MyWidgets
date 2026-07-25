#!/bin/bash
# Build a signed (and optionally notarized) release of My Widgets.
#
# Signing is driven entirely by the environment, so the same script runs on a
# laptop and on a CI runner:
#
#   DEVELOPER_ID_APP   e.g. "Developer ID Application: Acme Oy (ABCDE12345)"
#                      unset → ad-hoc signing, fine for a local test build
#   DEVELOPMENT_TEAM   10-char Team ID (defaults to the one in project.yml)
#
# Notarization runs only when all three are set (Apple requires all of them):
#   NOTARY_APPLE_ID    Apple ID email
#   NOTARY_TEAM_ID     10-char Team ID
#   NOTARY_PASSWORD    app-specific password from appleid.apple.com
#
# Output: dist/MyWidgets.app, dist/MyWidgets-<version>.dmg
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="MyWidgets"
BUILD_DIR="$ROOT/.build"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

VERSION="$(sed -n 's/.*MARKETING_VERSION: "\([^"]*\)".*/\1/p' project.yml)"
BUILD_NUM="$(sed -n 's/.*CURRENT_PROJECT_VERSION: "\([^"]*\)".*/\1/p' project.yml)"
DMG="$DIST/$APP_NAME-$VERSION.dmg"

echo "==> $APP_NAME $VERSION (build $BUILD_NUM)"

# ── Sign mode ─────────────────────────────────────────────────────────────────
# Without a Developer ID we still produce a runnable .app (ad-hoc signed), so
# contributors can build and test without any Apple credentials.
if [ -n "${DEVELOPER_ID_APP:-}" ]; then
    if [ -n "${NOTARY_APPLE_ID:-}" ] && [ -n "${NOTARY_TEAM_ID:-}" ] && [ -n "${NOTARY_PASSWORD:-}" ]; then
        echo "==> sign mode: Developer ID + notarize"
    else
        echo "==> sign mode: Developer ID (notarization skipped — NOTARY_* incomplete)"
    fi
    SIGN_ARGS=(CODE_SIGN_IDENTITY="$DEVELOPER_ID_APP" CODE_SIGN_STYLE=Manual)
else
    echo "==> sign mode: ad-hoc (set DEVELOPER_ID_APP for a distributable build)"
    SIGN_ARGS=(CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO)
fi

[ -n "${DEVELOPMENT_TEAM:-}" ] && SIGN_ARGS+=(DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM")

# ── Build (Release) ───────────────────────────────────────────────────────────
# Release, not Debug: Debug widget extensions use a preview-dylib shim that
# WidgetKit won't reload outside Xcode, so a placed widget keeps stale code.
echo "==> generating project"
xcodegen generate >/dev/null

echo "==> building (Release)"
rm -rf "$BUILD_DIR" "$DIST"
mkdir -p "$DIST"
xcodebuild -project "$ROOT/$APP_NAME.xcodeproj" -scheme "$APP_NAME" \
    -destination "generic/platform=macOS" -configuration Release \
    -derivedDataPath "$BUILD_DIR" "${SIGN_ARGS[@]}" build >/dev/null
cp -R "$BUILD_DIR/Build/Products/Release/$APP_NAME.app" "$APP"
echo "    built $APP"

# xcodebuild signs the embedded widget extension inside-out for us; verify that
# rather than re-signing by hand, which is easy to get wrong for a bundle with
# an .appex inside.
if [ -n "${DEVELOPER_ID_APP:-}" ]; then
    echo "==> verifying signature"
    codesign --verify --deep --strict --verbose=2 "$APP"
fi

# ── Notarize + staple the .app ────────────────────────────────────────────────
notarize() {
    local target="$1" label="$2"
    local zip="$DIST/$label.notary.zip"
    local submit="$target"
    # notarytool takes a .zip/.dmg/.pkg — an .app must be zipped first.
    if [[ "$target" == *.app ]]; then
        /usr/bin/ditto -c -k --keepParent "$target" "$zip"
        submit="$zip"
    fi
    echo "==> notarizing $label (1–5 min)"
    /usr/bin/xcrun notarytool submit "$submit" \
        --apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" \
        --password "$NOTARY_PASSWORD" --wait
    echo "==> stapling $label"
    /usr/bin/xcrun stapler staple "$target"
    rm -f "$zip"
}

CAN_NOTARIZE=false
if [ -n "${DEVELOPER_ID_APP:-}" ] && [ -n "${NOTARY_APPLE_ID:-}" ] \
    && [ -n "${NOTARY_TEAM_ID:-}" ] && [ -n "${NOTARY_PASSWORD:-}" ]; then
    CAN_NOTARIZE=true
fi

if [ "$CAN_NOTARIZE" = true ]; then
    notarize "$APP" "$APP_NAME.app"
fi

# ── Package a .dmg ────────────────────────────────────────────────────────────
# Built from the stapled .app so the copy a user drags out is already trusted;
# the .dmg is then notarized in its own right so the download itself opens
# cleanly. hdiutil keeps this dependency-free (no dmgbuild/python needed).
echo "==> packaging $DMG"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

if [ "$CAN_NOTARIZE" = true ]; then
    codesign --force --timestamp --sign "$DEVELOPER_ID_APP" "$DMG"
    notarize "$DMG" "$APP_NAME.dmg"
fi

echo
echo "Done:"
echo "  $APP"
echo "  $DMG"
[ "$CAN_NOTARIZE" = true ] || echo "  (not notarized — Gatekeeper will warn on another Mac)"
