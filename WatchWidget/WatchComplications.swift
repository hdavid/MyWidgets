import WidgetKit
import SwiftUI

@main
struct WatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WindComplication()
        TemperatureComplication()
    }
}

// MARK: - Shared timeline
//
// One provider feeds both complications: they draw different slots of the same
// snapshot, and a shared last-good cache means adding the temperature
// complication costs no extra fetches beyond its own timeline's.

struct WatchWindEntry: TimelineEntry {
    let date: Date
    let snap: WindSnapshot?
    let stale: Bool
    let source: GrafanaSource?
}

struct WatchWindProvider: AppIntentTimelineProvider {
    /// Shown in the complication picker in front of the source name. Both
    /// complications share this provider, and the picker labels entries with
    /// the recommendation description alone — without this prefix the Wind and
    /// Temperature entries would read identically.
    var pickerLabel = "Wind"

    func placeholder(in context: Context) -> WatchWindEntry {
        let source = GrafanaConfig.load().first
        return WatchWindEntry(date: Date(),
                              snap: source.flatMap { WindStore.load(for: $0.id) },
                              stale: false, source: source)
    }

    /// watchOS has no "Edit Widget" — the complication picker offers one entry
    /// per configured source instead, which this list supplies.
    func recommendations() -> [AppIntentRecommendation<SelectSourceIntent>] {
        GrafanaConfig.load().map { source in
            let intent = SelectSourceIntent()
            intent.source = SourceEntity(source)
            let name = source.title.isEmpty ? "Metrics" : source.title
            // Resolve to a plain String BEFORE it becomes a resource: an
            // interpolated *resource* is "formatted text", and WidgetKit traps
            // on those in recommendations — which kills the extension during
            // descriptor fetch and hides the complications from every picker.
            let label: String = "\(pickerLabel) · \(name)"
            return AppIntentRecommendation(intent: intent,
                                           description: LocalizedStringResource(stringLiteral: label))
        }
    }

    func snapshot(for configuration: SelectSourceIntent, in context: Context) async -> WatchWindEntry {
        await makeEntry(configuration.source?.id)
    }

    func timeline(for configuration: SelectSourceIntent, in context: Context) async -> Timeline<WatchWindEntry> {
        let entry = await makeEntry(configuration.source?.id)
        // Complications refresh on a tighter budget than home-screen widgets
        // (~4/hour all told), so ask for less than the iOS widget's 5 min.
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60)))
    }

    /// Same shape as the iOS widget's provider: fetch, cache, fall back.
    private func makeEntry(_ sourceID: String?) async -> WatchWindEntry {
        guard let source = GrafanaConfig.source(sourceID) else {
            return WatchWindEntry(date: Date(), snap: nil, stale: true, source: nil)
        }
        if let fresh = await Grafana.fetchAll(source) {
            WindStore.save(fresh, for: source.id)
            return WatchWindEntry(date: Date(), snap: fresh, stale: false, source: source)
        }
        return WatchWindEntry(date: Date(), snap: WindStore.load(for: source.id),
                              stale: true, source: source)
    }
}

// MARK: - Wind + direction

struct WindComplicationView: View {
    @Environment(\.widgetFamily) var family
    var entry: WatchWindEntry

    var body: some View {
        Group {
            if let source = entry.source, let snap = entry.snap {
                let r = WindReading(source: source, snap: snap)
                switch family {
                case .accessoryCorner:
                    Text(r.text(.primary) ?? "--")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(r.color(.primary))
                        .widgetCurvesContent()
                        .widgetLabel {
                            Text(cornerLabel(r))
                                .foregroundStyle(Pal.gray)
                        }
                case .accessoryInline:
                    Text(inlineText(r))
                case .accessoryRectangular:
                    VStack(alignment: .leading, spacing: 1) {
                        TitleRow(r: r, size: 13)
                        HStack(spacing: 6) {
                            PrimaryValue(r: r, size: 22)
                            SecondaryLine(r: r, size: 12, weight: .medium)
                        }
                        if let row = r.chipRows(max: 1).first {
                            ChipRow(r: r, slots: row, size: 12)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                default: // .accessoryCircular
                    ZStack {
                        AccessoryWidgetBackground()
                        if r.hasDirection {
                            WindRose(deg: r.direction, showLetters: false)
                                .padding(1)
                        }
                        Text(fmtN(r.value(.primary), 0))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(r.color(.primary))
                    }
                    .widgetLabel {
                        Text(cornerLabel(r))
                    }
                }
            } else {
                // First sync needs the watch app to have run once (that's what
                // activates WCSession and lands the phone's config push), so
                // say so where there is room for words.
                switch family {
                case .accessoryInline:
                    Text("Wind --")
                case .accessoryRectangular:
                    Text("No data — open the My Widgets watch app once to sync")
                        .font(.system(size: 11))
                        .foregroundStyle(Pal.gray)
                default:
                    ZStack {
                        AccessoryWidgetBackground()
                        Image(systemName: "wind")
                    }
                }
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    /// "NW · Gust 18" — direction plus whatever the secondary slot holds.
    private func cornerLabel(_ r: WindReading) -> String {
        var parts: [String] = []
        if let d = r.value(.direction) { parts.append(degToCompass(d)) }
        if let s = r.text(.secondary) { parts.append(s) }
        return parts.joined(separator: " · ")
    }

    private func inlineText(_ r: WindReading) -> String {
        var parts: [String] = []
        if let p = r.text(.primary) { parts.append(p) }
        if let d = r.value(.direction) { parts.append(degToCompass(d)) }
        return parts.isEmpty ? "Wind --" : parts.joined(separator: " ")
    }
}

struct WindComplication: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "WatchWind", intent: SelectSourceIntent.self,
                               provider: WatchWindProvider()) { entry in
            WindComplicationView(entry: entry)
        }
        .configurationDisplayName("Wind")
        .description("Live wind and direction from your Grafana.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner,
                            .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Temperature

struct TemperatureComplicationView: View {
    @Environment(\.widgetFamily) var family
    var entry: WatchWindEntry

    /// The first enabled slot on the temperature scale — same rule the wind
    /// views use to find their dew-spread reference.
    private var slot: MetricSlot? {
        entry.source?.slots.first { $0.scale == .temperature && $0.enabled && !$0.query.isEmpty }
    }

    private var value: Double? {
        guard let slot else { return nil }
        return entry.snap?.values[slot.id]
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Text(value.map { "Temp \(fmt1($0))°" } ?? "Temp --")
            case .accessoryCorner:
                Text(value.map { fmt1($0) + "°" } ?? "--")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(temperatureColor(value))
                    .widgetCurvesContent()
                    .widgetLabel {
                        // The curved gauge corner slots are designed around.
                        Gauge(value: min(max(value ?? -10, -10), 40), in: -10...40) {
                            EmptyView()
                        }
                        .tint(temperatureColor(value))
                    }
            case .accessoryRectangular:
                if let source = entry.source, let snap = entry.snap {
                    let r = WindReading(source: source, snap: snap)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(source.title)
                            .font(.system(size: 13, weight: .bold))
                            .lineLimit(1)
                        Text(value.map { fmt1($0) + "°" } ?? "--")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(temperatureColor(value))
                        // The big number above is already the temperature —
                        // fill the chip line with the *other* chips.
                        let others = source.chips.filter { $0.id != slot?.id }.prefix(3)
                        if !others.isEmpty {
                            ChipRow(r: r, slots: Array(others), size: 12)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("No data — open the My Widgets watch app once to sync")
                        .font(.system(size: 11))
                        .foregroundStyle(Pal.gray)
                }
            default: // .accessoryCircular
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: -2) {
                        Image(systemName: "thermometer.medium")
                            .font(.system(size: 11))
                            .foregroundStyle(Pal.gray)
                        Text(value.map { fmt1($0) + "°" } ?? "--")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(temperatureColor(value))
                    }
                }
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct TemperatureComplication: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "WatchTemp", intent: SelectSourceIntent.self,
                               provider: WatchWindProvider(pickerLabel: "Temperature")) { entry in
            TemperatureComplicationView(entry: entry)
        }
        .configurationDisplayName("Temperature")
        .description("Live temperature from your Grafana.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner,
                            .accessoryRectangular, .accessoryInline])
    }
}
