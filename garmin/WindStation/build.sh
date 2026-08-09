#!/bin/bash
# Build the Wind Station Connect IQ widget.
#
#   ./build.sh <device-id>          e.g. ./build.sh fenix7
#   ./build.sh <device-id> run      build, then launch in the simulator
#
# Requires device files downloaded via the Connect IQ SDK Manager (one-time
# Garmin developer login). monkeyc/monkeydo come from `brew install --cask
# connectiq`; the signing key is generated once next to this project:
#   openssl genrsa -out ../developer_key.pem 4096
#   openssl pkcs8 -topk8 -inform PEM -outform DER -nocrypt \
#       -in ../developer_key.pem -out ../developer_key.der
set -euo pipefail
cd "$(dirname "$0")"

DEVICE="${1:?usage: ./build.sh <device-id> [run]}"
KEY="../developer_key.der"
OUT="bin/WindStation-$DEVICE.prg"

[ -f "$KEY" ] || { echo "missing $KEY — see header comment"; exit 1; }
mkdir -p bin

# Bake tokens from garmin/local-tokens.json (gitignored) into the property
# defaults so the widget works without any settings entry; the clean
# properties.xml is restored even if the compile fails.
python3 scripts/bake_tokens.py inject
trap 'python3 scripts/bake_tokens.py restore' EXIT

monkeyc -o "$OUT" -f monkey.jungle -y "$KEY" -d "$DEVICE" -w
echo "built $OUT"

if [ "${2:-}" = "run" ]; then
    connectiq &
    sleep 3
    monkeydo "$OUT" "$DEVICE"
fi
