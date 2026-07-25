# My Widgets

Widgets for macOS, iOS and iPadOS: live metrics from your own Grafana, windguru
forecasts, webcam frames, and Claude Code usage. Each widget fetches its own
data, so nothing has to be running for them to stay fresh (the one exception is
Claude usage, which needs Keychain access and so is refreshed by the app).

| Widget | What it shows | Configured in |
|---|---|---|
| **Live Metrics** | Any metrics from your own Grafana — wind rose, headline value, coloured chips, background sparkline | Grafana tab |
| **Windguru Forecast** | Hourly wind / gust / direction / temperature, daylight hours, in a dense Windguru-style table | Windguru tab |
| **Webcam** | Latest frame from a still-image URL, click to open the page | Webcams tab |
| **Claude Usage** | 5 h / weekly / Fable quota per Claude Code account (macOS only) | Claude tab |

Add them with: right-click the desktop → **Edit Widgets** → **My Widgets**, or on
iOS long-press the home screen → **+**.

Claude Usage is macOS-only: it reads Claude Code's Keychain items by shelling out
to `security`, which iOS has no equivalent for. Everything else is identical on
both platforms.

**Live Metrics**, **Windguru Forecast** and **Webcam** are per-instance
configurable: add as many copies as you like, then right-click each one → **Edit
Widget** to choose which source, spot or webcam it shows. The pickers list
whatever you've defined in the app, so an entry added there is immediately
offered to every placed widget.

Every tab uses the same add/remove list: a card per entry with a delete button
and a disclosure holding its details.

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

### Moving config between devices

The App Group container is per-device, so the Mac and the phone don't share
settings. The **Config** tab exports everything as one JSON file and imports it
back — that's the route from Mac to iPhone. Grafana tokens are opt-in on export;
importing a token-less file keeps whatever tokens the target device already has,
so it can't silently wipe them.

## Building

Requires Xcode and [xcodegen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`). The `.xcodeproj` is generated from `project.yml` and
is not committed.

```bash
./install.sh                  # macOS: build Release, install to /Applications, restart widgets
./scripts/build-release.sh    # macOS: build + package dist/MyWidgets-<version>.dmg
```

It's one app, not two: a single multiplatform target builds for macOS, iOS and
iPadOS, so there is one scheme and one bundle id. For iOS, open the project and
pick an iPhone/iPad destination:

```bash
./scripts/configure.sh && open MyWidgets.xcodeproj
```

A device install needs a provisioning profile, so the iOS side uses automatic
signing and Xcode manages it — there's no Developer ID path like on the Mac. The
simulator needs nothing.

Every build path starts with `scripts/configure.sh`, which resolves your build
identity and generates the files that depend on it (`Shared/BuildConfig.generated.swift`,
both platforms' `.entitlements`, and the Xcode project). Values come from the
environment, then `local-config/build.env`, then the committed
`build.env.example` placeholders — so a fresh clone builds without setup.

`build-release.sh` works with no Apple credentials — it ad-hoc signs, which is
fine for local testing but will make Gatekeeper complain on another Mac. Set
`DEVELOPER_ID_APP` for a real signed build, and all three `NOTARY_*` variables
to also notarize and staple:

```bash
set -a; . ./.env.local; set +a     # see .env.local.example
./scripts/build-release.sh
```

### Forking

Copy `build.env.example` to `local-config/build.env` and set `BUNDLE_PREFIX`,
`APP_NAME` and `DEVELOPMENT_TEAM` to yours. Nothing else needs editing —
`configure.sh` derives the bundle ids and both App Groups from those three.

Note the App Group naming differs by platform, and both forms are mandatory:
macOS needs the Team ID prefix (`TEAMID.group.…`), iOS needs a `group.` prefix
and no team. Getting it wrong fails at runtime with a nil container URL, not at
build time.

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
App/          the app: entry point, window/scene shells, settings views
Widget/       widget definitions, timelines, views, configuration intents
Shared/       models, config, palette, shared UI — compiled into both targets
scripts/      configure, release build, CI secrets, local config sync
entitlements/ generated per platform (gitignored)
local-config/ this machine's real config and build identity (gitignored)
project.yml   xcodegen definition — 2 multiplatform targets: app + widget
```

Platform differences are `#if os(macOS)` in the source, not separate targets:
the menu-bar panel and login item, `SelfFetch.swift` (shells out to `security`),
`UsageWidget.swift` and `AccountSettingsView.swift`. What genuinely can't be
shared is conditioned per SDK in `project.yml` — signing, and the App Group,
which macOS and iOS spell differently.

Config that both targets read lives in `Shared/*Config.swift`, each backed by a
JSON file in the App Group container: `grafana.json`, `webcams.json`,
`windguru.json`, `accounts.json`.

Which entry a placed widget shows is *not* in those files — it's in the widget's
own `WidgetConfigurationIntent` (`Widget/WidgetIntents.swift`), which is how one
compiled widget kind can be added many times with different content.
