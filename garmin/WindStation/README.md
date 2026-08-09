# Wind Station — Garmin Connect IQ widget

Shows live wind from both stations — Moutiers (Vevor) and La Bernerie (WS90)
— querying the same Grafana `/api/ds/query` endpoints as the Apple widgets,
one batched POST per station. The glance shows one line per station
(`MOU 14.2 g18.4 NW`); the full widget mirrors the iOS medium widget (minus
watts/dew/humidity/max): compass rose with direction needle, big average,
gust, temperature, pressure + 3 h trend arrow (Moutiers only — Bernerie has
no pressure sensor), 1 h wind sparkline, and the measurement time.
SELECT/tap flips stations. Stations (hosts, queries, calibration factors)
are baked into `source/WindData.mc` — this is a private sideloaded app,
rebuild to change them.

It also publishes two watch-face **complications** ("Moutiers wind" /
"Bernerie wind", value like `12.3kn NW`) that Face It and CIQ watch faces
can subscribe to, kept fresh by a 15-minute background temporal event that
refetches both stations without opening the widget.

## One-time setup on the Mac

1. `brew install --cask connectiq connectiq-sdk-manager` (done)
2. Open **SdkManager.app**, sign in with a free Garmin developer account,
   download the current SDK and the target device(s). Device files land in
   `~/Library/Application Support/Garmin/ConnectIQ/Devices/`, where `monkeyc`
   finds them.
3. Signing key: already generated at `../developer_key.pem/.der` (gitignored).

## Build & simulate

    ./build.sh fenix7 run

## Getting it onto the watch

Private distribution = sideload (the Connect IQ store has no private apps):
plug the watch in via USB; it mounts as a drive — copy
`bin/WindStation-<device>.prg` into `/GARMIN/Apps/`. No account, review, or
cable-free updates; re-copy the file to update.

## Configuration (per user)

Tokens are NOT baked in. After installing, open Garmin Connect on the paired
iPhone → device → Connect IQ apps → Station Wind → Settings and paste the two
Grafana tokens (Moutiers and Bernerie are separate Grafana instances, so each
needs its own). Create dedicated read-only service-account tokens per person,
so they can be revoked independently.

## Trimming the manifest

`manifest.xml` lists a broad set of modern watches. Once the actual device is
known, prune the list — every listed product must have its device files
downloaded for a store build to pass.
