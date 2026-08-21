import WidgetKit
import SwiftUI

// MARK: - Timeline

struct StationEntry: TimelineEntry {
    let date: Date
    let snap: WindSnapshot?
    let stale: Bool
    /// Synthetic source rendering this station with the Grafana wind views —
    /// captured with the entry so the view and the values agree.
    let source: GrafanaSource?
    let configured: Bool
}

struct StationProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> StationEntry {
        let station = WindguruStationsConfig.load().first
        return StationEntry(date: Date(),
                            snap: station.flatMap { WindStore.load(for: storeKey($0)) },
                            stale: false,
                            source: station.map(WindguruStationDisplay.source),
                            configured: station?.isConfigured ?? false)
    }

    func snapshot(for configuration: SelectStationIntent, in context: Context) async -> StationEntry {
        await makeEntry(configuration.station?.id)
    }

    func timeline(for configuration: SelectStationIntent, in context: Context) async -> Timeline<StationEntry> {
        let entry = await makeEntry(configuration.station?.id)
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(5 * 60)))
    }

    private func storeKey(_ station: WindguruStation) -> String { "wgstation_\(station.id)" }

    private func makeEntry(_ stationID: String?) async -> StationEntry {
        guard let station = WindguruStationsConfig.station(stationID), station.isConfigured else {
            return StationEntry(date: Date(), snap: nil, stale: true, source: nil,
                                configured: false)
        }
        let source = WindguruStationDisplay.source(station)
        if let reading = await Windguru.stationCurrent(station: station.stationId) {
            let series = StationHistory.append(reading, for: station.id)
            let snap = WindguruStationDisplay.snapshot(reading, series: series)
            WindStore.save(snap, for: storeKey(station))
            // A station that stopped uploading still answers with its last
            // reading — that is data, not an outage, so `stale` stays false and
            // the "Measured at" age color says how old it is.
            return StationEntry(date: Date(), snap: snap, stale: false,
                                source: source, configured: true)
        }
        return StationEntry(date: Date(), snap: WindStore.load(for: storeKey(station)),
                            stale: true, source: source, configured: true)
    }
}

// MARK: - View

struct StationWidgetView: View {
    @Environment(\.widgetFamily) var family
    var entry: StationEntry

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
                NoDataView(message: entry.configured
                           ? "No data yet"
                           : "Add a station in the app’s Windguru tab")
            }
        }
        // Click opens the station's windguru page in the browser.
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

/// One kind, added as many times as you like — each copy picks its station.
struct WindguruStationWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "WindguruStation", intent: SelectStationIntent.self,
                               provider: StationProvider()) { entry in
            StationWidgetView(entry: entry)
        }
        .configurationDisplayName("Windguru Station")
        .description("Live wind from a windguru weather station. Right-click → Edit Widget to pick the station.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
