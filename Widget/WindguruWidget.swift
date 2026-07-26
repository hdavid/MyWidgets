import WidgetKit
import SwiftUI

// MARK: - Timeline

struct ForecastEntry: TimelineEntry {
    let date: Date
    let forecast: WindguruForecast?
    let stale: Bool
    /// Captured with the entry so the header names the spot the values came from.
    let spot: WindguruSpot?
    /// Constituents for the tide row, cached per spot; nil inland.
    let tide: TideHarmonics?
}

struct ForecastProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ForecastEntry {
        let spot = WindguruConfig.load().first
        return ForecastEntry(date: Date(),
                             forecast: spot.flatMap { ForecastStore.load(for: $0.id) },
                             stale: false, spot: spot,
                             tide: spot.flatMap { TideStore.load(for: $0.id) })
    }

    func snapshot(for configuration: SelectSpotIntent, in context: Context) async -> ForecastEntry {
        await makeEntry(configuration.spot?.id)
    }

    func timeline(for configuration: SelectSpotIntent, in context: Context) async -> Timeline<ForecastEntry> {
        let entry = await makeEntry(configuration.spot?.id)
        // Models refresh a few times a day; an hourly reload keeps the strip
        // anchored to the current time cheaply.
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60 * 60)))
    }

    private func makeEntry(_ spotID: String?) async -> ForecastEntry {
        guard let spot = WindguruConfig.spot(spotID) else {
            return ForecastEntry(date: Date(), forecast: nil, stale: true, spot: nil, tide: nil)
        }
        let fresh = await Windguru.fetch(spot)
        if let fresh { ForecastStore.save(fresh, for: spot.id) }
        // Read the tide after the fetch: that is what caches the constituents
        // the first time a spot is shown.
        return ForecastEntry(date: Date(),
                             forecast: fresh ?? ForecastStore.load(for: spot.id),
                             stale: fresh == nil, spot: spot,
                             tide: TideStore.load(for: spot.id))
    }
}

// MARK: - Windguru cell palette (sampled from windguru.cz table cells)

private typealias RGB = (r: Double, g: Double, b: Double)

/// Exact wind-speed cell colors read from windguru's rendered table
/// (integer-knot samples); >27 kn extended toward their magenta end.
private let wgWindStops: [(Double, RGB)] = [
    (0,  (255, 255, 255)), (4,  (255, 255, 255)), (5,  (244, 254, 254)),
    (6,  (216, 253, 251)), (7,  (192, 252, 249)), (8,  (156, 250, 246)),
    (9,  (94, 248, 220)),  (10, (78, 249, 183)),  (11, (47, 251, 110)),
    (12, (32, 253, 74)),   (13, (22, 253, 52)),   (14, (43, 252, 0)),
    (15, (58, 252, 0)),    (16, (112, 248, 0)),   (17, (168, 245, 0)),
    (18, (199, 243, 0)),   (19, (255, 224, 4)),   (20, (255, 194, 11)),
    (22, (255, 152, 20)),  (24, (255, 78, 38)),   (26, (255, 44, 68)),
    (27, (255, 40, 85)),   (30, (255, 20, 120)),  (35, (220, 0, 180)),
]

/// Temperature cell colors sampled 14…28 °C; ends clamped, cool side extended.
private let wgTempStops: [(Double, RGB)] = [
    (0,  (180, 235, 255)), (8,  (235, 250, 210)), (12, (255, 235, 100)),
    (14, (255, 219, 58)),  (16, (255, 202, 37)),  (18, (255, 191, 24)),
    (20, (255, 165, 2)),   (22, (255, 150, 9)),   (24, (255, 128, 18)),
    (26, (255, 93, 32)),   (28, (255, 79, 38)),   (32, (255, 50, 50)),
]

private func wgColor(_ v: Double?, stops: [(Double, RGB)]) -> WGInk {
    guard let v else { return wgInk((255, 255, 255)) }
    var lo = stops[0], hi = stops[stops.count - 1]
    if v <= lo.0 { return wgInk(lo.1) }
    if v >= hi.0 { return wgInk(hi.1) }
    for i in 1..<stops.count where stops[i].0 >= v {
        lo = stops[i - 1]; hi = stops[i]; break
    }
    let t = (v - lo.0) / (hi.0 - lo.0)
    return wgInk((lo.1.r + (hi.1.r - lo.1.r) * t,
                  lo.1.g + (hi.1.g - lo.1.g) * t,
                  lo.1.b + (hi.1.b - lo.1.b) * t))
}

private func wgRGB(_ c: RGB) -> Color {
    Color(red: c.r / 255, green: c.g / 255, blue: c.b / 255)
}

// MARK: - Keeping the digits readable on every cell

/// A cell and the ink that reads on it.
private struct WGInk {
    let bg: Color
    let fg: Color
}

/// How readable a cell has to be, in APCA lightness contrast (Lc).
///
/// APCA's own guidance: 90 is body-text ideal, 75 the floor for normal small
/// text, 60 for small BOLD text, 45 headline-only. These digits are 10–12 pt
/// and mostly bold in a table you glance at, so 60.
///
/// APCA rather than WCAG 2 because WCAG 2 is wrong about exactly this palette.
/// Its ratio is driven by relative luminance, which the red channel barely
/// moves, so a saturated red reads as "light" to the formula: on 26 kn
/// (#ff2c44) WCAG scores black 5.7:1 against white 3.7:1 and picks black,
/// while APCA scores black 41.6 against white 67.9. The eye agrees with APCA —
/// black on those cells was the complaint that started this.
private let wgMinLc = 60.0

private let wgBlackInk: RGB = (0, 0, 0)
private let wgWhiteInk: RGB = (255, 255, 255)

/// APCA screen luminance (W3C draft constants 0.98G-4g). Note this is a plain
/// 2.4 power curve, not sRGB's piecewise transfer function — APCA models the
/// display, not the encoding.
private func wgY(_ c: RGB) -> Double {
    let y = 0.2126729 * pow(c.r / 255, 2.4)
          + 0.7151522 * pow(c.g / 255, 2.4)
          + 0.0721750 * pow(c.b / 255, 2.4)
    // Black clamp: stops near-black backgrounds from overstating contrast.
    return y < 0.022 ? y + pow(0.022 - y, 1.414) : y
}

/// APCA lightness contrast of `text` on `bg`, returned as a magnitude — the
/// sign only encodes which of the two is darker, which the caller knows.
private func wgLc(text: RGB, on bg: RGB) -> Double {
    let yt = wgY(text), yb = wgY(bg)
    guard abs(yb - yt) >= 0.0005 else { return 0 }
    // The two polarities get different exponents: light-on-dark needs more
    // separation than dark-on-light to read the same, which is the whole
    // reason APCA sees this palette differently from WCAG.
    let s = yb > yt ? (pow(yb, 0.56) - pow(yt, 0.57)) * 1.14    // dark ink
                    : (pow(yb, 0.65) - pow(yt, 0.62)) * 1.14    // light ink
    guard abs(s) >= 0.1 else { return 0 }                       // APCA low clip
    return abs(s > 0 ? s - 0.027 : s + 0.027) * 100
}

private func wgMix(_ c: RGB, _ t: Double, toward d: RGB) -> RGB {
    (c.r + (d.r - c.r) * t, c.g + (d.g - c.g) * t, c.b + (d.b - c.b) * t)
}

/// Windguru's cell color, plus black or white digits — whichever APCA prefers.
///
/// The ink flips at 22.8 kn and 24.2 °C, and that choice alone is enough
/// almost everywhere: sweeping both ramps at 0.1 steps, only 12 of 400 wind
/// cells and 30 of 500 temperature cells fail `wgMinLc` even with their better
/// ink, all of them in the narrow band around the flip where neither ink is
/// comfortable. Those get nudged away from their ink by the smallest amount
/// that clears the bar — every other cell keeps windguru's color exactly.
///
/// Measured at 0.07–0.08 µs for a cell that needs no nudge and 0.88 µs for one
/// that does, so a full 126-cell large-family table costs 9.8 µs — nothing
/// against the layout the widget host already does for it.
private func wgInk(_ c: RGB) -> WGInk {
    let black = wgLc(text: wgBlackInk, on: c)
    let white = wgLc(text: wgWhiteInk, on: c)
    let ink = black >= white ? wgBlackInk : wgWhiteInk
    guard max(black, white) < wgMinLc else { return WGInk(bg: wgRGB(c), fg: wgRGB(ink)) }
    // Contrast rises monotonically as the cell moves away from its ink, so
    // bisect; 12 steps land well inside a 1/255 color step.
    let away = ink == wgBlackInk ? wgWhiteInk : wgBlackInk
    var lo = 0.0, hi = 1.0
    for _ in 0..<12 {
        let t = (lo + hi) / 2
        if wgLc(text: ink, on: wgMix(c, t, toward: away)) < wgMinLc { lo = t } else { hi = t }
    }
    return WGInk(bg: wgRGB(wgMix(c, hi, toward: away)), fg: wgRGB(ink))
}

/// Cloud cover, clear to overcast — windguru greys these cells the same way.
private let wgCloudStops: [(Double, RGB)] = [
    (0,   (255, 255, 255)), (20,  (240, 242, 245)), (40, (214, 218, 224)),
    (60,  (184, 190, 198)), (80,  (150, 157, 167)), (100, (116, 124, 136)),
]

/// Rain, mm/h. Deliberately blue rather than grey: the row swaps between two
/// quantities, so the colour has to say which one you are looking at.
private let wgRainStops: [(Double, RGB)] = [
    (0,   (222, 240, 255)), (0.5, (160, 210, 250)), (1, (104, 178, 245)),
    (2,   (56, 142, 232)),  (4,   (30, 104, 200)),  (8, (22, 70, 160)),
]

private func wgWindColor(_ v: Double?) -> WGInk { wgColor(v, stops: wgWindStops) }
private func wgTempColor(_ v: Double?) -> WGInk { wgColor(v, stops: wgTempStops) }
private func wgCloudColor(_ v: Double?) -> WGInk { wgColor(v, stops: wgCloudStops) }
private func wgRainColor(_ v: Double?) -> WGInk { wgColor(v, stops: wgRainStops) }

/// What the combined sky row shows for one hour: rain when there is any,
/// otherwise cloud cover. Below 0.05 mm/h windguru's own table prints nothing,
/// and a "0.0" cell would just be noise.
private func wgSkyCell(_ p: ForecastPoint) -> (text: String, ink: WGInk)? {
    if let rain = p.rain, rain >= 0.05 {
        // One decimal only while it fits the cell; heavy rain is a whole number.
        let text = rain < 10 ? String(format: "%.1f", rain) : String(Int(rain.rounded()))
        return (text, wgRainColor(rain))
    }
    guard let cloud = p.cloud else { return nil }
    return (fmt0(cloud), wgCloudColor(cloud))
}

// MARK: - Table line (windguru-style rows: hours / wind / gust / arrows)

private struct WGCellMetrics {
    var labelSize: CGFloat
    var valueSize: CGFloat
    var cellHeight: CGFloat
    var arrowSize: CGFloat
    /// Horizontal gap between columns. Windguru's table separates cells with a
    /// hairline border, so this stays tiny — the row reads as one solid block.
    var gap: CGFloat = 1
    /// Vertical gap between rows, same reasoning as `gap`.
    var rowGap: CGFloat = 1
    /// Windguru cells are square; 1pt only takes the hard edge off the pixels.
    var corner: CGFloat = 1
    /// The tide row carries no digits, so it can be shorter than a value cell
    /// and still read — the bar heights are the whole message.
    var tideHeight: CGFloat = 10
    /// The sky row is the only one that can print three characters ("100", or
    /// "0.4" of rain), so it gets its own size rather than making every column
    /// wide enough for a value the other rows never reach.
    var skySize: CGFloat { valueSize - 2 }
}

/// Windguru's header band tints alternate day-by-day, which is what separates
/// one day from the next in a strip that has no weekday column.
private let wgBandTints: [Color] = [Color.primary.opacity(0.13),
                                    Color.primary.opacity(0.05)]

private struct ForecastLine: View {
    let points: [ForecastPoint]
    let columns: Int
    let m: WGCellMetrics
    var showTemp = true
    /// Cloud cover, swapped for rain in the hours it rains.
    var showSky = false
    /// Only drawn when the spot has tide constituents cached.
    var tide: TideHarmonics?
    /// Height, in cm from mean sea level, at or above which a bar goes green.
    var greenAbove: Double?

    private let cal = Calendar.current

    /// Zero-padded hour, windguru-style ("08", "14") — no "h", which buys width.
    private func hourLabel(_ i: Int) -> String {
        String(format: "%02d", cal.component(.hour, from: points[i].time))
    }

    /// True on the first column of a new day — that label is tinted instead of
    /// carrying a weekday prefix, which would never fit in a narrow cell.
    private func startsNewDay(_ i: Int) -> Bool {
        i > 0 && !cal.isDate(points[i].time, inSameDayAs: points[i - 1].time)
    }

    /// Alternating header tint, keyed to the absolute day so it stays stable
    /// across lines and across month boundaries.
    ///
    /// Cheap enough measured (56 calls ≈ 0.002 ms), but there is no reason to
    /// repeat it per cell when a line spans at most two days.
    private func bandTint(_ i: Int) -> Color {
        let day = cal.ordinality(of: .day, in: .era, for: points[i].time) ?? 0
        return wgBandTints[day % 2]
    }

    var body: some View {
        // Row order follows windguru: wind, gusts, direction, temperature.
        VStack(spacing: m.rowGap) {
            row { i in
                Text(hourLabel(i))
                    .font(.system(size: m.labelSize, weight: .semibold))
                    // Grey marks the columns filled in from the longer-range
                    // model, so the drop in resolution is visible in the table
                    // and not only in the header. A new day still wins the
                    // colour: knowing where Tuesday starts matters more.
                    .foregroundStyle(startsNewDay(i) ? Pal.blue
                                     : (points[i].tail == true ? Pal.gray : .primary))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity,
                           minHeight: m.labelSize + 2, maxHeight: m.labelSize + 2)
                    .background(bandTint(i), in: RoundedRectangle(cornerRadius: m.corner))
            }
            row { i in
                cell(fmt0(points[i].wind), ink: wgWindColor(points[i].wind), bold: true)
            }
            row { i in
                cell(fmt0(points[i].gust), ink: wgWindColor(points[i].gust), bold: false)
            }
            row { i in
                // Windguru's own convention, which is the opposite of the
                // weather-vane one the Live Metrics wind rose uses: the arrow
                // flies WITH the wind, showing where it blows TO. `dir` is the
                // meteorological direction it comes from, hence the half turn.
                // Reading this table against windguru.cz beats internal
                // consistency with a widget that sits next to it.
                Image(systemName: "arrow.up")
                    .font(.system(size: m.arrowSize, weight: .bold))
                    .rotationEffect(.degrees(points[i].dir + 180))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity,
                           minHeight: m.arrowSize + 2, maxHeight: m.arrowSize + 2)
            }
            if showTemp {
                row { i in
                    cell(fmt0(points[i].temp), ink: wgTempColor(points[i].temp), bold: false)
                }
            }
            if showSky {
                row { i in
                    // One row, two quantities: cloud cover in percent, replaced
                    // by rain in mm/h whenever there is any. The palette is what
                    // tells them apart — grey is sky, blue is water.
                    if let sky = wgSkyCell(points[i]) {
                        cell(sky.text, ink: sky.ink, bold: false, size: m.skySize)
                    } else {
                        cell("", ink: wgCloudColor(nil), bold: false, size: m.skySize)
                    }
                }
            }
            if let tide {
                row { i in
                    let height = Tide.height(tide, at: points[i].time)
                    tideBar(Tide.level(tide, from: height),
                            high: greenAbove.map { height >= $0 } ?? false)
                }
            }
        }
    }

    /// One table row: `columns` equal-width slots (blank past the data's end).
    private func row<Content: View>(@ViewBuilder _ content: @escaping (Int) -> Content) -> some View {
        HStack(spacing: m.gap) {
            // Only the columns that have data — a short final line simply ends,
            // rather than padding with placeholder views the host must lay out.
            ForEach(0..<min(columns, points.count), id: \.self) { i in
                content(i).frame(maxWidth: .infinity)
            }
        }
    }

    /// One hour of tide, as a column filling from the bottom.
    ///
    /// `level` is already scaled against the spot's mean high/low water, so a
    /// neap day sits visibly short of a spring day rather than every day being
    /// redrawn full-height — which is exactly what a per-window normalisation
    /// would have thrown away.
    ///
    /// `high` colours the hours that clear the spot's configured level, so the
    /// green band is the answer to "when can I go", read straight off the row.
    private func tideBar(_ level: Double, high: Bool) -> some View {
        let ink = high ? Pal.green : Pal.chart
        return ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: m.corner)
                .fill(ink.opacity(0.15))
            RoundedRectangle(cornerRadius: m.corner)
                .fill(ink)
                // A floor of 1pt: an empty cell at dead low water reads as
                // missing data rather than as the bottom of the curve.
                .frame(height: max(1, m.tideHeight * level))
        }
        .frame(maxWidth: .infinity, minHeight: m.tideHeight, maxHeight: m.tideHeight)
    }

    /// `size` overrides the row's font, which only the sky row needs: every
    /// other row tops out at two characters, but cloud cover reaches "100" and
    /// three digits at `valueSize` are wider than a 14-column cell — they came
    /// out as "1…".
    private func cell(_ text: String, ink: WGInk, bold: Bool,
                      size: CGFloat? = nil) -> some View {
        Text(text)
            // Semibold rather than regular for the gust and temperature rows:
            // `wgMinLc` is APCA's threshold for small BOLD text, and regular
            // weight at this size would want Lc 75, which no saturated cell in
            // the ramp reaches with either ink. The wind row stays fully bold,
            // so the rows still read as a hierarchy.
            .font(.system(size: size ?? m.valueSize, weight: bold ? .bold : .semibold))
            // Black or white per cell, decided by APCA in `wgInk`, and fixed
            // rather than `.primary`: the cell color doesn't change with the
            // system appearance, so neither should its ink.
            .foregroundStyle(ink.fg)
            .lineLimit(1)
            // No minimumScaleFactor: it makes SwiftUI lay each Text out at
            // several font sizes, and this table has hundreds of cells that the
            // widget HOST process has to lay out. The values are two or three
            // characters in a cell sized for them, so it never bought anything.
            //
            // Fixed height, not minimum: windguru's cells are tighter than a
            // text line's natural height, and digits have no descenders to clip.
            .frame(maxWidth: .infinity,
                   minHeight: m.cellHeight, maxHeight: m.cellHeight)
            .background(ink.bg, in: RoundedRectangle(cornerRadius: m.corner))
    }
}

// MARK: - Header

private struct ForecastHeader: View {
    let title: String
    let forecast: WindguruForecast
    let stale: Bool
    var size: CGFloat
    var days: String = ""

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: size, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if !days.isEmpty {
                Text(days)
                    .font(.system(size: size - 2, weight: .semibold))
                    .foregroundStyle(Pal.gray)
                    .lineLimit(1)
            }
            Spacer(minLength: 2)
            if stale {
                Text("offline")
                    .font(.system(size: size - 2, weight: .semibold))
                    .foregroundStyle(Pal.red)
            }
            Text(forecast.model)
                .font(.system(size: size - 2, weight: .semibold))
                .foregroundStyle(Pal.gray)
                .lineLimit(1)
            // Named, never silent: the last columns come from a coarser model,
            // and the header is where you find out which.
            if let tail = forecast.tailModel {
                Text("+\(tail)")
                    .font(.system(size: size - 3, weight: .medium))
                    .foregroundStyle(Pal.gray)
                    .lineLimit(1)
                    .layoutPriority(-1)
            }
        }
    }
}

// MARK: - Family layouts (2 dense windguru-style lines)

private struct ForecastGrid: View {
    let title: String
    let forecast: WindguruForecast
    let stale: Bool
    let columns: Int
    let lines: Int
    let m: WGCellMetrics
    var headerSize: CGFloat
    var showTemp = true
    var showSky = false
    var tide: TideHarmonics?
    var greenAbove: Double?
    /// Gap between two stacked day-strips — the only generous space in the grid.
    var lineGap: CGFloat = 5

    var body: some View {
        let pts = forecast.upcoming(hours: columns * lines)
        VStack(alignment: .leading, spacing: lineGap) {
            ForecastHeader(title: title, forecast: forecast, stale: stale,
                           size: headerSize, days: dayRange(pts))
                .padding(.bottom, -1)
            ForEach(0..<lines, id: \.self) { line in
                let slice = Array(pts.dropFirst(line * columns).prefix(columns))
                if !slice.isEmpty {
                    ForecastLine(points: slice, columns: columns, m: m,
                                 showTemp: showTemp, showSky: showSky, tide: tide,
                                 greenAbove: greenAbove)
                }
            }
            Spacer(minLength: 0)
        }
        // Own margins instead of WidgetKit's default (which is much larger):
        // windguru runs its table nearly edge to edge, so keep these minimal.
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
    }

    /// "Sat" or "Sat–Sun" — the days covered, so hour cells need no weekday.
    private func dayRange(_ pts: [ForecastPoint]) -> String {
        guard let first = pts.first, let last = pts.last else { return "" }
        let f = DateFormatter()
        f.dateFormat = "EEE"
        let a = f.string(from: first.time), b = f.string(from: last.time)
        return a == b ? a : "\(a)–\(b)"
    }
}

struct ForecastWidgetView: View {
    @Environment(\.widgetFamily) var family
    var entry: ForecastEntry

    var body: some View {
        Group {
            if let spot = entry.spot, let f = entry.forecast,
               !f.upcoming(hours: 1).isEmpty {
                // 14 columns is one full daylight span (08h…21h), so each line
                // reads as roughly one day of the strip.
                switch family {
                case .systemMedium:
                    ForecastGrid(title: spot.heading, forecast: f, stale: entry.stale,
                                 columns: 14, lines: 2,
                                 m: .init(labelSize: 9, valueSize: 11, cellHeight: 12,
                                          arrowSize: 9),
                                 headerSize: 11, lineGap: 4)
                case .systemLarge, .systemExtraLarge:
                    // The only family with the height for the sky and tide
                    // rows: they add 26 pt per line, which medium hasn't got.
                    ForecastGrid(title: spot.heading, forecast: f, stale: entry.stale,
                                 columns: 14, lines: 3,
                                 m: .init(labelSize: 10, valueSize: 12, cellHeight: 14,
                                          arrowSize: 10),
                                 headerSize: 13, showSky: true, tide: entry.tide,
                                 greenAbove: spot.greenAboveMSL, lineGap: 5)
                default:
                    ForecastGrid(title: spot.heading, forecast: f, stale: entry.stale,
                                 columns: 7, lines: 2,
                                 m: .init(labelSize: 9, valueSize: 10, cellHeight: 11,
                                          arrowSize: 8),
                                 headerSize: 10, lineGap: 4)
                }
            } else {
                NoForecastView(message: entry.spot?.isConfigured == true
                               ? "No forecast yet"
                               : "Add a windguru spot in the app’s Windguru tab")
            }
        }
        .widgetURL(entry.spot.flatMap {
            $0.isConfigured ? Windguru.pageURL(spot: $0.spotId) : nil
        })
        .containerBackground(for: .widget) { Pal.bg }
    }
}

// MARK: - No-data fallback

struct NoForecastView: View {
    var message = "No forecast yet"

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "cloud.sun.fill")
                .font(.title)
                .foregroundStyle(Pal.gray)
            Text(message)
                .font(.caption)
                .foregroundStyle(Pal.gray)
                .multilineTextAlignment(.center)
        }
        .padding(8)
    }
}

// MARK: - Widget

/// One kind, added as many times as you like — each copy picks its spot.
struct ForecastWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "WindguruForecast", intent: SelectSpotIntent.self,
                               provider: ForecastProvider()) { entry in
            ForecastWidgetView(entry: entry)
        }
        .configurationDisplayName("Windguru Forecast")
        .description("Hourly wind forecast (knots), daylight hours. Right-click → Edit Widget to pick the spot.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
