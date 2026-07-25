#!/usr/bin/env bash
# Move widget config between local-config/ and the installed app's App Group
# container.
#
# local-config/ holds the real endpoints and tokens for THIS machine's install.
# It is gitignored: the committed defaults are deliberately generic so nothing
# private ends up in the repo, while the values you actually run with stay on
# disk next to the code.
#
#   ./scripts/local-config.sh apply    local-config/ → the installed app
#   ./scripts/local-config.sh save     the installed app → local-config/
#   ./scripts/local-config.sh diff     show what differs
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCAL="$ROOT/local-config"
GROUP="JHV8UWZS57.group.systems.holonic.MyWidgets"
CONTAINER="$HOME/Library/Group Containers/$GROUP"

# accounts.json is not listed: it holds Keychain item names per Claude account
# and is managed entirely in the app's Claude tab.
FILES=(grafana.json webcams.json windguru.json)

usage() { echo "usage: $0 {apply|save|diff}" >&2; exit 1; }
[ $# -eq 1 ] || usage

case "$1" in
apply)
    [ -d "$CONTAINER" ] || { echo "✗ container not found — run ./install.sh and open the app once" >&2; exit 1; }
    for f in "${FILES[@]}"; do
        if [ -f "$LOCAL/$f" ]; then
            cp "$LOCAL/$f" "$CONTAINER/$f"
            echo "→ $f"
        fi
    done
    # Widgets cache the last good values; nudge them to re-read the new config.
    killall chronod 2>/dev/null || true
    echo "Applied. Widgets will pick it up on their next refresh."
    ;;
save)
    mkdir -p "$LOCAL"
    for f in "${FILES[@]}"; do
        if [ -f "$CONTAINER/$f" ]; then
            cp "$CONTAINER/$f" "$LOCAL/$f"
            echo "← $f"
        fi
    done
    echo "Saved to local-config/ (gitignored)."
    ;;
diff)
    for f in "${FILES[@]}"; do
        echo "── $f"
        diff -u "$LOCAL/$f" "$CONTAINER/$f" 2>/dev/null || true
    done
    ;;
*) usage ;;
esac
