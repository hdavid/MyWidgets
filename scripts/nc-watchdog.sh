#!/usr/bin/env bash
# Detect and clear the NotificationCenter 100%-CPU spin.
#
# The spin is an Apple bug in the widget host's SwiftUI view graph
# (GraphHost.runTransaction → DisplayList.HostedViewState churning forever) —
# sampled and attributed on 2026-07-26 and again 2026-08-01, both times with
# zero MyWidgets frames and our extension idle. It tends to re-trip when the
# host respawns after an install.sh (which kills chronod). The only remedy is
# SIGTERM; launchd relaunches NotificationCenter instantly and the fresh
# instance sits idle. See scripts/diagnose-widget-hang.sh for the manual
# deep-dive version.
#
# Run by the LaunchAgent systems.holonic.MyWidgets.ncwatch every 2 minutes.
# Detection is two consecutive 5-second CPU-time windows ≥ 80% of a core —
# a real spin holds ~100% indefinitely, while user interaction (scrolling the
# widget sidebar) bursts and settles, so double-checking avoids false kills.
#
# Testing: pass a PID as $1 to point the detector at any process.
set -euo pipefail

LOG_DIR="$HOME/Library/Logs/MyWidgets"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/nc-watchdog.log"

# ps cputime is "MM:SS.ss" or "HH:MM:SS.ss" — normalize to seconds.
cpu_secs() {
    ps -p "$1" -o cputime= 2>/dev/null | awk -F: '{ s = $NF; m = (NF >= 2) ? $(NF-1) : 0; h = (NF >= 3) ? $(NF-2) : 0; printf "%.2f\n", h*3600 + m*60 + s }'
}

# One 5-second window; prints the CPU-seconds consumed in it, or exits 0
# silently if the process vanished mid-measure (nothing to do then).
window() {
    local pid="$1" t0 t1
    t0="$(cpu_secs "$pid")"; [ -z "$t0" ] && exit 0
    sleep 5
    t1="$(cpu_secs "$pid")"; [ -z "$t1" ] && exit 0
    awk -v a="$t1" -v b="$t0" 'BEGIN { printf "%.2f\n", a - b }'
}

busy() { awk -v d="$1" 'BEGIN { exit !(d >= 4.0) }'; }

pid="${1:-$(pgrep -x NotificationCenter | head -1 || true)}"
[ -z "$pid" ] && exit 0

w1="$(window "$pid")"
busy "$w1" || exit 0

# Looks hot — let any legitimate burst settle, then confirm.
sleep 10
w2="$(window "$pid")"
busy "$w2" || { echo "$(date '+%F %T') pid $pid burst (${w1}s/5s) but settled (${w2}s/5s) — left alone" >> "$LOG"; exit 0; }

kill -TERM "$pid" 2>/dev/null || true
echo "$(date '+%F %T') pid $pid SPINNING (${w1}s then ${w2}s per 5s window) — sent SIGTERM, launchd respawns it" >> "$LOG"
