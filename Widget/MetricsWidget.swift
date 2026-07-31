import WidgetKit
import SwiftUI

// MARK: - Timeline

struct WindEntry: TimelineEntry {
    let date: Date
    let snap: WindSnapshot?
    let stale: Bool
    /// Captured with the entry so the view renders against the same source the
    /// values were fetched with.
    let source: GrafanaSource?
}

struct WindProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WindEntry {
        let source = GrafanaConfig.load().first
        return WindEntry(date: Date(),
                         snap: source.flatMap { WindStore.load(for: $0.id) },
                         stale: false, source: source)
    }

    func snapshot(for configuration: SelectSourceIntent, in context: Context) async -> WindEntry {
        await makeEntry(configuration.source?.id)
    }

    func timeline(for configuration: SelectSourceIntent, in context: Context) async -> Timeline<WindEntry> {
        let entry = await makeEntry(configuration.source?.id)
        // Ask for a refresh in 5 minutes; WidgetKit grants what its budget
        // allows (typically 5–15 min for a visible widget).
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(5 * 60)))
    }

    /// The widget fetches its own data — no companion app needs to run.
    private func makeEntry(_ sourceID: String?) async -> WindEntry {
        guard let source = GrafanaConfig.source(sourceID) else {
            return WindEntry(date: Date(), snap: nil, stale: true, source: nil)
        }
        if let fresh = await Grafana.fetchAll(source) {
            WindStore.save(fresh, for: source.id)
            return WindEntry(date: Date(), snap: fresh, stale: false, source: source)
        }
        // Network/server problem (or no token yet): fall back to the last good
        // snapshot so the widget keeps showing something.
        return WindEntry(date: Date(), snap: WindStore.load(for: source.id),
                         stale: true, source: source)
    }
}

// MARK: - View

struct WindWidgetView: View {
    @Environment(\.widgetFamily) var family
    var entry: WindEntry

    var body: some View {
        Group {
            if let source = entry.source, let snap = entry.snap {
                let r = WindReading(source: source, snap: snap)
                switch family {
                case .systemMedium:
                    MediumWindView(r: r, stale: entry.stale)
                        .padding(.horizontal, 12).padding(.vertical, 9)
                case .systemLarge, .systemExtraLarge:
                    LargeWindView(r: r, stale: entry.stale)
                        .padding(.horizontal, 14).padding(.vertical, 11)
                default:
                    SmallWindView(r: r, stale: entry.stale)
                        .padding(.horizontal, 11).padding(.vertical, 9)
                }
            } else {
                NoDataView(message: entry.source?.isConfigured == true
                           ? "No data yet"
                           : "Add a Grafana URL and token in the app’s Grafana tab")
            }
        }
        // Click opens the dashboard configured for this source, in the browser.
        .opensInBrowser(entry.source.flatMap { URL(string: $0.dashboardURL) })
        .containerBackground(for: .widget) {
            ZStack(alignment: .bottom) {
                Pal.bg
                if let snap = entry.snap, !snap.series.isEmpty {
                    GeometryReader { geo in
                        Sparkline(values: snap.series)
                            .frame(height: geo.size.height * 0.36)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }
            }
        }
    }
}

/// One kind, added as many times as you like — each copy picks its source.
struct MetricsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "LiveMetrics", intent: SelectSourceIntent.self,
                               provider: WindProvider()) { entry in
            WindWidgetView(entry: entry)
        }
        .configurationDisplayName("Live Metrics")
        .description("Live values from your Grafana. Right-click → Edit Widget to pick the source.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        // WidgetKit insets widget content by a generous default margin, which is
        // what pushed the title away from the top edge. Opt out and set our own
        // below, so the layout gets the full height.
        .contentMarginsDisabled()
    }
}
