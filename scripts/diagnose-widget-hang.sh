#!/usr/bin/env bash
# Capture what the widget host is doing. Run this WHILE the widget area is
# beachballing — the whole point is catching the main thread mid-spin.
#
# What to look for in the output:
#   "main thread: IDLE"  → the hang is not in NotificationCenter's main thread;
#                          look at chronod or the widget extension instead.
#   "main thread: BUSY"  → it is spinning. The hot path that follows says where.
#                          Frames under GraphHost.runTransaction identify which
#                          view tree SwiftUI is churning on.
#
# Needs no root: both hosts run as you.
set -euo pipefail

OUT="${TMPDIR:-/tmp}/widget-hang-$(date +%H%M%S)"
mkdir -p "$OUT"
echo "==> capturing to $OUT"

for name in NotificationCenter chronod; do
    pid="$(pgrep -x "$name" | head -1 || true)"
    if [ -z "$pid" ]; then
        echo "  $name: not running"
        continue
    fi
    sample "$pid" 5 -file "$OUT/$name.txt" >/dev/null 2>&1 || true
    python3 - "$OUT/$name.txt" "$name" <<'PY'
import sys, re
path, name = sys.argv[1], sys.argv[2]
try:
    lines = open(path).read().split('\n')
except OSError:
    print(f"  {name}: no sample"); raise SystemExit

start = next((i for i, l in enumerate(lines) if 'com.apple.main-thread' in l), None)
if start is None:
    print(f"  {name}: no main thread in sample"); raise SystemExit

total = int(re.match(r'\s*(\d+)', lines[start]).group(1))
frame = re.compile(r'^([\s+!:|]*)(\d+) (.+)$')

stack = []
for l in lines[start+1:]:
    if re.match(r'^\s+\d+ Thread_', l):
        break
    m = frame.match(l)
    if m:
        stack.append((int(m.group(2)), m.group(3)))

# A thread parked in the event loop bottoms out in a kernel wait. One that is
# spinning keeps almost all its samples in userland frames past the run loop.
waits = ('mach_msg2_trap', '__psynch_cvwait', 'semaphore_wait', 'kevent_id',
         '__workq_kernreturn', 'read', 'select')
leaf_waits = [n for n, s in stack if any(w in s for w in waits) and n >= total * 0.9]
busy = not leaf_waits

print(f"  {name}: main thread: {'BUSY (spinning)' if busy else 'IDLE (parked in event loop)'}"
      f"  [{total} samples]")
if busy:
    marker = next((i for i, (n, s) in enumerate(stack) if 'runTransaction' in s), 0)
    for n, s in stack[marker:]:
        if n >= total * 0.10:
            print(f"      {n:5} ({n*100//total:3}%) {s[:100]}")
PY
done

echo
echo "Full samples kept in $OUT — attach those if the hot path is inconclusive."
