import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Tide widgets
//
// Two kinds on the same engine: "TideToday" draws the curve from midnight over
// a configurable 24/36/48 h span (36 h default — tonight and tomorrow morning
// always in view) with the now-marker (plus lock-screen accessory faces on
// iOS); "TideDays" the week ahead. Both show the coefficient, high/low times and the configured
// threshold lines — the today chart also labels when each threshold is
// crossed, both ways. Heights are synthesized locally from cached
// constituents (TideModel) — the providers need the network at most once,
// and the click-through opens the maree.info page.
// The selection intent lives in WidgetIntents.swift (the watch compiles it
// too, for the matching complications).

// MARK: Entry & provider

struct TideEntry: TimelineEntry {
    let date: Date
    /// Curve start and sampling step for mapping index → time.
    let start: Date
    let step: TimeInterval
    let curve: [Double]
    let extremes: [TideExtreme]
    let thresholds: [Double]
    /// Threshold crossings inside the curve range, for the on-line labels.
    let crossings: [(threshold: Double, date: Date, rising: Bool)]
    /// Instant status for the accessory (lock screen) families.
    let status: TideModel.Status?
    let title: String
    let url: URL?
    let days: Int
    /// True when constituents were never cached and could not be fetched.
    let empty: Bool

    static func placeholder(days: Int) -> TideEntry {
        TideEntry(date: Date(), start: Date(), step: 600, curve: [], extremes: [],
                  thresholds: [], crossings: [], status: nil, title: "Tide",
                  url: nil, days: days, empty: true)
    }
}

/// Both kinds share the maths; the span in hours decides how far past
/// midnight the curve runs. Everything after the one-time constituent fetch
/// is local synthesis, so timelines are generated in bulk (a moving
/// now-marker for today, a daily roll for the days view).
struct TideProvider: AppIntentTimelineProvider {
    /// Fixed span in hours (days widget); nil = the widget's own span setting.
    let fixedHours: Int?

    private func hours(for configuration: SelectTideLocationIntent) -> Int {
        fixedHours ?? configuration.span.hours
    }

    func placeholder(in context: Context) -> TideEntry {
        .placeholder(days: ((fixedHours ?? TideSpan.h36.hours) + 23) / 24)
    }

    func snapshot(for configuration: SelectTideLocationIntent, in context: Context) async -> TideEntry {
        await makeEntry(configuration.location?.id, at: Date(),
                        hours: hours(for: configuration))
    }

    func timeline(for configuration: SelectTideLocationIntent, in context: Context) async -> Timeline<TideEntry> {
        // One shared fetch, then cheap per-instant entries: every 20 min for
        // the now-marker, refreshed after the last one.
        let now = Date()
        let hours = hours(for: configuration)
        var entries: [TideEntry] = []
        for i in 0..<9 {
            entries.append(await makeEntry(configuration.location?.id,
                                           at: now.addingTimeInterval(Double(i) * 1200),
                                           hours: hours))
        }
        return Timeline(entries: entries, policy: .atEnd)
    }

    private func makeEntry(_ locationID: String?, at date: Date, hours: Int) async -> TideEntry {
        let days = (hours + 23) / 24
        guard let loc = TideConfig.location(locationID) else { return .placeholder(days: days) }
        let (local, brest) = await TideModel.harmonics(for: loc)
        guard let local, let mapping = loc.heightMapping else {
            return TideEntry(date: date, start: date, step: 600, curve: [], extremes: [],
                             thresholds: loc.thresholds, crossings: [], status: nil,
                             title: loc.title, url: loc.pageURL, days: days, empty: true)
        }
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .hour, value: hours, to: start)
            ?? start.addingTimeInterval(Double(hours) * 3600)
        let range = start...end
        return TideEntry(
            date: date,
            start: start,
            step: 600,
            curve: TideModel.curve(local, mapping: mapping, in: range),
            extremes: TideModel.extremes(local, mapping: mapping, brest: brest, in: range),
            thresholds: loc.thresholds,
            crossings: loc.thresholds.flatMap {
                TideModel.crossings(local, mapping: mapping, of: $0, in: range)
            },
            status: TideModel.status(local, mapping: mapping, brest: brest,
                                     thresholds: loc.thresholds, at: date),
            title: loc.title,
            url: loc.pageURL,
            days: days,
            empty: false)
    }
}

// MARK: Views

struct TideWidgetView: View {
    @Environment(\.widgetFamily) var family
    var entry: TideEntry
    /// Show the now-marker (today widget only).
    var nowMarker: Bool

    var body: some View {
        Group {
            switch family {
            #if os(iOS)
            case .accessoryCircular:
                TideCircularView(status: entry.status, title: entry.title)
            case .accessoryRectangular:
                TideRectangularView(status: entry.status, title: entry.title)
            case .accessoryInline:
                Text(TideText.inline(entry.status))
            #endif
            default:
                if entry.empty {
                    Text("No tide data — needs one fetch")
                        .font(.system(size: 11))
                        .foregroundStyle(Pal.gray)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // The chart is the containerBackground (full bleed, like
                    // the wind sparkline); only the header floats above it.
                    VStack(alignment: .leading, spacing: 2) {
                        TideHeader(entry: entry)
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 7)
                    .padding(.horizontal, 10)
                }
            }
        }
        .opensInBrowser(entry.url)
        .containerBackground(for: .widget) { background }
    }

    @ViewBuilder private var background: some View {
        #if os(iOS)
        let accessory = family == .accessoryCircular || family == .accessoryRectangular
            || family == .accessoryInline
        #else
        let accessory = false
        #endif
        if accessory {
            Color.clear
        } else if entry.empty {
            Pal.bg
        } else {
            ZStack {
                Pal.bg
                TideChart(start: entry.start, step: entry.step, curve: entry.curve,
                          extremes: entry.extremes, thresholds: entry.thresholds,
                          crossings: entry.crossings, days: entry.days,
                          date: entry.date, nowMarker: nowMarker, topInset: 22)
            }
        }
    }
}

private struct TideHeader: View {
    let entry: TideEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(entry.title)
                .font(.system(size: 12, weight: .semibold))
            Spacer(minLength: 0)
            // Today's (or the first day's) coefficients, morning · evening.
            let cal = Calendar.current
            let coefs = entry.extremes
                .filter { $0.isHigh && cal.isDate($0.date, inSameDayAs: entry.date) }
                .compactMap(\.coefficient)
            if !coefs.isEmpty {
                (Text("coef ").foregroundColor(Pal.gray)
                    + Text(coefs.map(String.init).joined(separator: " · "))
                    .foregroundColor(coefs.contains { $0 >= 90 } ? Pal.orange : .primary))
                    .font(.system(size: 12, weight: .medium))
            }
        }
    }
}

// MARK: Widgets

private var tideTodayFamilies: [WidgetFamily] {
    #if os(iOS)
    [.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline]
    #else
    [.systemSmall, .systemMedium]
    #endif
}

struct TideTodayWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "TideToday", intent: SelectTideLocationIntent.self,
                               provider: TideProvider(fixedHours: nil)) { entry in
            TideWidgetView(entry: entry, nowMarker: true)
        }
        .configurationDisplayName("Tide today")
        .description("The tide curve, coefficient and thresholds from midnight over 24, 36 or 48 hours — pick the span in Edit Widget.")
        .supportedFamilies(tideTodayFamilies)
        .contentMarginsDisabled()
    }
}

struct TideDaysWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "TideDays", intent: SelectTideLocationIntent.self,
                               provider: TideProvider(fixedHours: 7 * 24)) { entry in
            TideWidgetView(entry: entry, nowMarker: false)
        }
        .configurationDisplayName("Tide week")
        .description("The week ahead: tide curve, coefficients and thresholds.")
        .supportedFamilies([.systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
