import WidgetKit
import SwiftUI

// MARK: - Timeline

struct ForecastEntry: TimelineEntry {
    let date: Date
    let forecast: WindguruForecast?
    let stale: Bool
}

struct ForecastProvider: TimelineProvider {
    func placeholder(in context: Context) -> ForecastEntry {
        ForecastEntry(date: Date(), forecast: ForecastStore.load(), stale: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (ForecastEntry) -> Void) {
        if context.isPreview {
            completion(ForecastEntry(date: Date(), forecast: ForecastStore.load(), stale: false))
            return
        }
        Task { completion(await makeEntry()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ForecastEntry>) -> Void) {
        Task {
            let entry = await makeEntry()
            // Models refresh a few times a day; an hourly reload keeps the
            // strip anchored to the current time cheaply.
            let next = Date().addingTimeInterval(60 * 60)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    private func makeEntry() async -> ForecastEntry {
        if let fresh = await Windguru.fetch(WindguruConfig.load()) {
            ForecastStore.save(fresh)
            return ForecastEntry(date: Date(), forecast: fresh, stale: false)
        }
        return ForecastEntry(date: Date(), forecast: ForecastStore.load(), stale: true)
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

private func wgColor(_ v: Double?, stops: [(Double, RGB)]) -> Color {
    guard let v else { return Color(red: 1, green: 1, blue: 1) }
    var lo = stops[0], hi = stops[stops.count - 1]
    if v <= lo.0 { return wgRGB(lo.1) }
    if v >= hi.0 { return wgRGB(hi.1) }
    for i in 1..<stops.count where stops[i].0 >= v {
        lo = stops[i - 1]; hi = stops[i]; break
    }
    let t = (v - lo.0) / (hi.0 - lo.0)
    return wgRGB((lo.1.r + (hi.1.r - lo.1.r) * t,
                  lo.1.g + (hi.1.g - lo.1.g) * t,
                  lo.1.b + (hi.1.b - lo.1.b) * t))
}

private func wgRGB(_ c: RGB) -> Color {
    Color(red: c.r / 255, green: c.g / 255, blue: c.b / 255)
}

private func wgWindColor(_ v: Double?) -> Color { wgColor(v, stops: wgWindStops) }
private func wgTempColor(_ v: Double?) -> Color { wgColor(v, stops: wgTempStops) }

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
                    .foregroundStyle(startsNewDay(i) ? Pal.blue : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity,
                           minHeight: m.labelSize + 2, maxHeight: m.labelSize + 2)
                    .background(bandTint(i), in: RoundedRectangle(cornerRadius: m.corner))
            }
            row { i in
                cell(fmt0(points[i].wind), bg: wgWindColor(points[i].wind), bold: true)
            }
            row { i in
                cell(fmt0(points[i].gust), bg: wgWindColor(points[i].gust), bold: false)
            }
            row { i in
                // Weather-vane convention: points where the wind comes FROM.
                Image(systemName: "arrow.up")
                    .font(.system(size: m.arrowSize, weight: .bold))
                    .rotationEffect(.degrees(points[i].dir))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity,
                           minHeight: m.arrowSize + 2, maxHeight: m.arrowSize + 2)
            }
            if showTemp {
                row { i in
                    cell(fmt0(points[i].temp), bg: wgTempColor(points[i].temp), bold: false)
                }
            }
        }
    }

    /// One table row: `columns` equal-width slots (blank past the data's end).
    private func row<Content: View>(@ViewBuilder _ content: @escaping (Int) -> Content) -> some View {
        HStack(spacing: m.gap) {
            ForEach(0..<columns, id: \.self) { i in
                Group {
                    if i < points.count { content(i) } else { Color.clear }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func cell(_ text: String, bg: Color, bold: Bool) -> some View {
        Text(text)
            .font(.system(size: m.valueSize, weight: bold ? .bold : .regular))
            .foregroundStyle(.black)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            // Fixed, not minimum: windguru's cells are tighter than a text
            // line's natural height, and digits have no descenders to clip.
            .frame(maxWidth: .infinity,
                   minHeight: m.cellHeight, maxHeight: m.cellHeight)
            .background(bg, in: RoundedRectangle(cornerRadius: m.corner))
    }
}

// MARK: - Header

private struct ForecastHeader: View {
    let forecast: WindguruForecast
    let stale: Bool
    var size: CGFloat
    var days: String = ""

    var body: some View {
        HStack(spacing: 4) {
            Text("Les Moutiers en Retz")
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
        }
    }
}

// MARK: - Family layouts (2 dense windguru-style lines)

private struct ForecastGrid: View {
    let forecast: WindguruForecast
    let stale: Bool
    let columns: Int
    let lines: Int
    let m: WGCellMetrics
    var headerSize: CGFloat
    var showTemp = true
    /// Gap between two stacked day-strips — the only generous space in the grid.
    var lineGap: CGFloat = 5

    var body: some View {
        let pts = forecast.upcoming(hours: columns * lines)
        VStack(alignment: .leading, spacing: lineGap) {
            ForecastHeader(forecast: forecast, stale: stale, size: headerSize,
                           days: dayRange(pts))
                .padding(.bottom, -1)
            ForEach(0..<lines, id: \.self) { line in
                let slice = Array(pts.dropFirst(line * columns).prefix(columns))
                if !slice.isEmpty {
                    ForecastLine(points: slice, columns: columns, m: m, showTemp: showTemp)
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
            if let f = entry.forecast, !f.upcoming(hours: 1).isEmpty {
                // 14 columns is one full daylight span (08h…21h), so each line
                // reads as roughly one day of the strip.
                switch family {
                case .systemMedium:
                    ForecastGrid(forecast: f, stale: entry.stale, columns: 14, lines: 2,
                                 m: .init(labelSize: 9, valueSize: 11, cellHeight: 12,
                                          arrowSize: 9),
                                 headerSize: 11, lineGap: 4)
                case .systemLarge, .systemExtraLarge:
                    ForecastGrid(forecast: f, stale: entry.stale, columns: 14, lines: 4,
                                 m: .init(labelSize: 10, valueSize: 12, cellHeight: 14,
                                          arrowSize: 10),
                                 headerSize: 13, lineGap: 5)
                default:
                    ForecastGrid(forecast: f, stale: entry.stale, columns: 7, lines: 2,
                                 m: .init(labelSize: 9, valueSize: 10, cellHeight: 11,
                                          arrowSize: 8),
                                 headerSize: 10, lineGap: 4)
                }
            } else {
                NoForecastView()
            }
        }
        .widgetURL(Windguru.pageURL(spot: WindguruConfig.load().spotId))
        .containerBackground(for: .widget) { Pal.bg }
    }
}

// MARK: - No-data fallback

struct NoForecastView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "cloud.sun.fill")
                .font(.title)
                .foregroundStyle(Pal.gray)
            Text("No forecast yet")
                .font(.caption)
                .foregroundStyle(Pal.gray)
        }
    }
}

// MARK: - Widget

struct MoutiersForecastWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MoutiersForecast", provider: ForecastProvider()) { entry in
            ForecastWidgetView(entry: entry)
        }
        .configurationDisplayName("Moutiers Forecast")
        .description("Windguru hourly wind forecast (knots), daylight hours")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
