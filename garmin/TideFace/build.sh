#!/bin/bash
# Build the Tide Face watch face.
#
#   ./build.sh <device-id>          e.g. ./build.sh venu2plus
#   ./build.sh <device-id> run      build, then launch in the simulator
#
# No token baking here — the face fetches nothing: wind arrives through the
# Wind Station widget's published complication, the tide is computed offline.
set -euo pipefail
cd "$(dirname "$0")"

DEVICE="${1:?usage: ./build.sh <device-id> [run]}"
KEY="../developer_key.der"
OUT="bin/TideFace-$DEVICE.prg"

[ -f "$KEY" ] || { echo "missing $KEY — see WindStation/build.sh header"; exit 1; }
mkdir -p bin

monkeyc -o "$OUT" -f monkey.jungle -y "$KEY" -d "$DEVICE" -w
echo "built $OUT"

if [ "${2:-}" = "run" ]; then
    connectiq &
    sleep 3
    monkeydo "$OUT" "$DEVICE"
fi
