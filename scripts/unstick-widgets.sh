#!/usr/bin/env bash
# Restart the macOS widget hosts when the widget area beachballs or the panel
# gets stuck open.
#
# Both processes are relaunched automatically, so this is safe — it's the same
# thing install.sh does to make placed widgets pick up new extension code.
#
# Note: `launchctl kickstart -k` does NOT work for chronod ("Operation not
# permitted while System Integrity Protection is engaged"), so a plain SIGTERM
# is the only option. Repeated restarts in quick succession spend launchd's
# exponential-throttling budget; if widgets stay blank afterwards, wait a minute
# instead of running this again.
set -euo pipefail

for name in NotificationCenter chronod; do
    if pkill -x "$name" 2>/dev/null; then
        echo "→ restarted $name"
    else
        echo "  $name was not running"
    fi
done

sleep 4
for name in NotificationCenter chronod; do
    pid="$(pgrep -x "$name" | head -1 || true)"
    echo "  $name: ${pid:-still down (launchd may be throttling — give it a minute)}"
done
