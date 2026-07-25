# My Widgets

macOS desktop widgets for live weather, forecasts, webcams and Claude Code usage.
Each widget fetches its own data, so nothing has to be running for them to stay
fresh (the one exception is Claude usage, which needs Keychain access and so is
refreshed by the app).

| Widget | What it shows | Configured in |
|---|---|---|
| **Live Metrics** | Any metrics from your own Grafana — wind rose, headline value, coloured chips, background sparkline | Grafana tab |
| **Moutiers Forecast** | Windguru hourly wind / gust / direction / temperature, daylight hours, in a dense Windguru-style table | Windguru tab |
| **Webcam** | Latest frame from a still-image URL, click to open the page | Webcams tab |
| **Claude Usage** | 5 h / weekly / Fable quota per Claude Code account | Claude tab |

Add them with: right-click the desktop → **Edit Widgets** → **My Widgets**.

**Live Metrics** and **Webcam** are per-instance configurable: add as many copies
as you like, then right-click each one → **Edit Widget** to choose which Grafana
source or which webcam it shows. The pickers list whatever you've defined in the
app, so a source added there is immediately offered to every placed widget.

## Configuration

Everything is configured in the app window — no editing source, no secrets in
the repo. Settings are written to the shared App Group container so the widget
extension reads the same values.

Real endpoints and tokens are **not** in this repo — the committed defaults are
generic placeholders. See [Local config](#local-config) for keeping your own
values on disk without committing them.

### Grafana (Live Metrics)

Add one *source* per Grafana instance (or per dashboard you care about) — enter
its URL and a **service-account token**, then define one *slot* per thing you
want drawn. A slot is a raw InfluxQL query plus how to present it:

- **Role** — where it lands in the layout: `Big number`, `Secondary`,
  `Tertiary`, `Rose (degrees)`, `Sparkline`, or `Chip`. Chips fill rows of three
  in the order listed. Roles other than `Chip` fill one place, so the first
  enabled slot with that role wins.
- **Label / Unit / decimals** — how the number is printed, e.g. `Gust 12.4kn`.
- **Scale** — which colour ramp tints it (wind, temperature, humidity,
  pressure, dew spread, solar, or plain).
- **Trend query** — optional second query read as "the value a while ago";
  when set, a tendency arrow (↑↗→↘↓) is appended. That's the 3 h pressure trend.

**Save & test** runs every query and reports which slots came back empty, with a
live preview of each slot's rendered text and colour.

**Duplicate** copies a source with fresh ids — the quick path to a second
station with the same slot shapes but a different host or measurement names.

The layout skeleton itself (rose + big value + secondary line, then chip rows)
is fixed in code — see `Widget/WindViews.swift`.

### Webcams

Add one entry per camera. Point each at a still image the camera overwrites
(typically a `latest.jpg`) and set a refresh interval. Placed widgets pick their
camera in **Edit Widget**.

### Local config

`local-config/` is gitignored and holds the real values for this machine's
install — endpoints, dashboard URLs and Grafana tokens. It exists so those live
next to the code without ever being committed:

```bash
./scripts/local-config.sh apply   # local-config/ → the installed app
./scripts/local-config.sh save    # the installed app → local-config/
./scripts/local-config.sh diff
```

Edit settings in the app, then `save` to snapshot them; on a fresh install,
`apply` to restore. The files are the same JSON the app writes into the App
Group container.

## Building

Requires Xcode and [xcodegen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`). The `.xcodeproj` is generated from `project.yml` and
is not committed.

```bash
./install.sh                  # build Release, install to /Applications, restart widgets
./scripts/build-release.sh    # build + package dist/MyWidgets-<version>.dmg
```

`build-release.sh` works with no Apple credentials — it ad-hoc signs, which is
fine for local testing but will make Gatekeeper complain on another Mac. Set
`DEVELOPER_ID_APP` for a real signed build, and all three `NOTARY_*` variables
to also notarize and staple:

```bash
set -a; . ./.env.local; set +a     # see .env.local.example
./scripts/build-release.sh
```

### Forking

Two identifiers are tied to the original developer account and need changing:
`DEVELOPMENT_TEAM` in `project.yml`, and the App Group
(`<TEAMID>.group.systems.holonic.MyWidgets`) in `App/App.entitlements` and
`Widget/Widget.entitlements`. The group's team prefix must match the team the
app is signed with, or the app and widget can't share their config.

## Releasing

Push a `v*` tag and GitHub Actions builds, signs, notarizes and attaches a
`.dmg` to a Release:

```bash
git tag v2.0.0 && git push origin v2.0.0
```

The workflow (`.github/workflows/release-macos.yml`) needs these repository
secrets, which `./scripts/setup-github-secrets.sh /path/to/cert.p12` will set
for you from a local `.env.local`:

| Secret | What it is |
|---|---|
| `MACOS_CERTIFICATE_P12` | base64 of your Developer ID Application `.p12` (cert **plus** private key) |
| `MACOS_CERTIFICATE_PWD` | the password you set when exporting that `.p12` |
| `DEVELOPER_ID_APP` | identity name, e.g. `Developer ID Application: Acme Oy (ABCDE12345)` |
| `NOTARY_APPLE_ID` | Apple ID email |
| `NOTARY_TEAM_ID` | 10-character Team ID |
| `NOTARY_PASSWORD` | app-specific password from appleid.apple.com |

The workflow signs in a throwaway keychain rather than the login keychain: a CI
runner has no UI session, so signing against the login keychain fails with
`errSecInternalComponent`.

## Layout

```
App/          the settings window and menu-bar panel (app target)
Widget/       widget definitions, timelines, views, configuration intents
Shared/       models, config, palette — compiled into both targets
scripts/      release build, CI secret setup, local config sync
local-config/ this machine's real config (gitignored)
project.yml   xcodegen project definition
```

Config that both targets read lives in `Shared/*Config.swift`, each backed by a
JSON file in the App Group container: `grafana.json`, `webcams.json`,
`windguru.json`, `accounts.json`.

Which entry a placed widget shows is *not* in those files — it's in the widget's
own `WidgetConfigurationIntent` (`Widget/WidgetIntents.swift`), which is how one
compiled widget kind can be added many times with different content.
