import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Tide complication
//
// A tide clock on the wrist: circular face with a needle (up = high water,
// down = low water) over horizontal threshold chords, plus rectangular /
// corner / inline faces with the coefficient, current height and the ETA to
// each threshold. All families draw one TideModel.Status; the views live in
// Shared/TideComplicationViews.swift, shared with the iOS lock screen.
// Synthesis is local (Tide.swift) — after the one-time constituent fetch the
// complication needs no network at all, so the timeline is a dense run of
// precomputed instants and the refresh budget is spent on nothing.

struct TideComplicationEntry: TimelineEntry {
    let date: Date
    let status: TideModel.Status?
    let title: String
    let locationID: String
}

struct TideComplicationProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TideComplicationEntry {
        let first = TideConfig.load().first
        return TideComplicationEntry(date: Date(), status: nil,
                                     title: first?.title ?? "Tide",
                                     locationID: first?.id ?? "")
    }

    /// watchOS has no "Edit Widget" — one picker entry per configured
    /// location (same pattern as the wind complications; keep the labels
    /// plain Strings, see the note in WatchWindProvider.recommendations).
    func recommendations() -> [AppIntentRecommendation<SelectTideLocationIntent>] {
        TideConfig.load().map { loc in
            let intent = SelectTideLocationIntent()
            intent.location = TideLocationEntity(loc)
            let label: String = "Tide · \(loc.title)"
            return AppIntentRecommendation(intent: intent,
                                           description: LocalizedStringResource(stringLiteral: label))
        }
    }

    func snapshot(for configuration: SelectTideLocationIntent, in context: Context) async -> TideComplicationEntry {
        await entries(configuration.location?.id, count: 1).first
            ?? placeholder(in: context)
    }

    func timeline(for configuration: SelectTideLocationIntent, in context: Context) async -> Timeline<TideComplicationEntry> {
        // 12 instants 10 min apart — 2 h of needle movement per refresh,
        // all computed locally.
        let list = await entries(configuration.location?.id, count: 12)
        return Timeline(entries: list, policy: .atEnd)
    }

    private func entries(_ locationID: String?, count: Int) async -> [TideComplicationEntry] {
        guard let loc = TideConfig.location(locationID) else { return [] }
        let (local, brest) = await TideModel.harmonics(for: loc)
        let now = Date()
        return (0..<count).map { i in
            let at = now.addingTimeInterval(Double(i) * 600)
            return TideComplicationEntry(
                date: at,
                status: local.flatMap {
                    TideModel.status($0, offset: loc.tideOffset, brest: brest,
                                     thresholds: loc.thresholds, at: at)
                },
                title: loc.title,
                locationID: loc.id)
        }
    }
}

struct TideComplicationView: View {
    @Environment(\.widgetFamily) var family
    var entry: TideComplicationEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Text(TideText.inline(entry.status))
            case .accessoryRectangular:
                TideRectangularView(status: entry.status, title: entry.title)
            case .accessoryCorner:
                if let status = entry.status {
                    Text("\(status.height.formatted(.number.precision(.fractionLength(1))))m")
                        .font(.system(size: 18, weight: .bold))
                        .widgetCurvesContent()
                        .widgetLabel { Text(TideText.label(status)) }
                } else {
                    Text("--")
                }
            default: // .accessoryCircular
                TideCircularView(status: entry.status, title: entry.title)
            }
        }
        // A tap opens the watch app straight on this location's tide page.
        .widgetURL(URL(string: "mywidgets://tide/\(entry.locationID)"))
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct TideComplication: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "WatchTide", intent: SelectTideLocationIntent.self,
                               provider: TideComplicationProvider()) { entry in
            TideComplicationView(entry: entry)
        }
        .configurationDisplayName("Tide")
        .description("Tide clock with coefficient, height and threshold ETA.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner,
                            .accessoryRectangular, .accessoryInline])
    }
}
