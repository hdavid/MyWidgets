#!/bin/bash
# Build and install My Widgets (wind + webcams + Claude usage).
#
# Architecture:
#  - Wind & webcam widgets fetch their own data in the widget extension.
#  - Claude usage is fetched by the app every 5 min (keychain access needs the
#    app side), written to the App Group; the widget also self-fetches when
#    the shared snapshot is stale. The app registers itself as a login item.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"   # xcodegen resolves project.yml from the working directory
BUILD_DIR="${TMPDIR:-/tmp}/MyWidgetsBuild"
APP_SRC="$BUILD_DIR/Build/Products/Release/MyWidgets.app"
APP_DST="/Applications/MyWidgets.app"

# Auto-bump the build number: the widget gallery caches an extension's widget
# list per bundle version, so every install MUST have a new version or newly
# added widgets won't appear.
CUR=$(sed -n 's/.*CURRENT_PROJECT_VERSION: "\([0-9]*\)".*/\1/p' project.yml)
NEW=$((CUR + 1))
sed -i '' "s/CURRENT_PROJECT_VERSION: \"$CUR\"/CURRENT_PROJECT_VERSION: \"$NEW\"/" project.yml
echo "==> Build number: $CUR → $NEW"

# Release (NOT Debug): Debug widget extensions use a preview-dylib shim that
# WidgetKit won't reload outside Xcode, so a placed widget keeps old code.
echo "==> Building (Release)…"
bash scripts/configure.sh
xcodebuild -project "$ROOT/MyWidgets.xcodeproj" -scheme MyWidgets \
    -destination "generic/platform=macOS" \
    -configuration Release -derivedDataPath "$BUILD_DIR" build >/dev/null
echo "    built."

echo "==> Installing app to $APP_DST"
osascript -e 'quit app "MyWidgets"' 2>/dev/null || true
sleep 1
rm -rf "$APP_DST"
cp -R "$APP_SRC" "$APP_DST"

echo "==> Registering with Launch Services and starting"
LSR=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSR" -f "$APP_DST"

# Force WidgetKit to pick up the new extension binary for already-placed widgets
# (a timeline reload re-runs the old code; only restarting the host reloads it).
#
# `killall`, not `launchctl kickstart -k` — SIP refuses to kickstart
# com.apple.chronod ("Operation not permitted while System Integrity Protection
# is engaged"), so a plain SIGTERM is the only thing that works here.
#
# Note this spends launchd's exponential-throttling budget for chronod. One
# install is fine; a tight rebuild loop is not — after a handful of restarts in
# quick succession launchd backs off, and placed widgets go blank or stop
# updating until it relents. If that happens, wait a minute rather than killing
# it again.
killall chronod 2>/dev/null || true
open "$APP_DST"

cat <<EOF

Done. "My Widgets" is installed; the app fetches Claude usage in the
background (launch-at-login) — wind and webcams need no app at all.

Add widgets (only a user gesture can do this):
  • Desktop: right-click → Edit Widgets → "My Widgets"
  • Right-click a placed widget → Edit Widget to pick which source/spot/webcam.

Configure Claude accounts in the app's "Accounts" tab.
EOF
