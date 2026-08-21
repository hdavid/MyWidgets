import Foundation

// MARK: - Configured stations (shared via the App Group container)

/// One windguru live weather station. Unlike a forecast spot, a station is a
/// real anemometer somebody uploads to windguru — the same kind of thing our
/// own Grafana stations are, so the widget renders it with the same views.
struct WindguruStation: Codable, Identifiable, Equatable {
    var id: String
    /// Widget heading. Empty falls back to "Station <id>"; "Save & test" fills
    /// it with the station's own name when left empty.
    var title: String
    /// The number in the station page URL (windguru.cz/station/2323).
    /// 0 means "not configured yet".
    var stationId: Int

    init(id: String = UUID().uuidString, title: String = "", stationId: Int = 0) {
        self.id = id
        self.title = title
        self.stationId = stationId
    }

    var isConfigured: Bool { stationId > 0 }
    var heading: String { title.isEmpty ? "Station \(stationId)" : title }
}

enum WindguruStationsConfig {
    static let fileName = "wgstations.json"

    static var fileURL: URL? { ConfigStore.url(fileName) }

    static func load() -> [WindguruStation] {
        guard let data = ConfigStore.read(fileName),
              let stations = try? JSONDecoder().decode([WindguruStation].self, from: data)
        else { return [] }
        return stations
    }

    /// The station a widget instance is bound to, falling back to the first one
    /// so a widget placed before anything was configured still shows something.
    static func station(_ id: String?) -> WindguruStation? {
        let all = load()
        guard let id else { return all.first }
        return all.first { $0.id == id } ?? all.first
    }

    @discardableResult
    static func save(_ stations: [WindguruStation]) -> Bool {
        guard let url = ConfigStore.writeURL(fileName) else { return false }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(stations) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}

// MARK: - Rendering a station with the Grafana wind views

/// The wind views draw from a (GrafanaSource, WindSnapshot) pair, so a station
/// gets a synthetic source with the fixed slot set a station reports — same
/// units and color scales as the Grafana widget. The slot queries are the
/// placeholder "station": nothing fetches them (the reading comes from the
/// iapi), but `GrafanaSource.slot(_:)` skips empty-query slots, so they must
/// not be "".
enum WindguruStationDisplay {
    static func source(_ station: WindguruStation) -> GrafanaSource {
        GrafanaSource(
            id: "wgstation-\(station.id)",
            title: station.heading,
            dashboardURL: Windguru.stationPageURL(station: station.stationId).absoluteString,
            slots: [
                MetricSlot(id: "avg", role: .primary, unit: "kn", decimals: 1,
                           scale: .wind, query: "station"),
                MetricSlot(id: "gust", role: .secondary, label: "Gust", decimals: 1,
                           scale: .wind, query: "station"),
                MetricSlot(id: "dir", role: .direction, unit: "°", query: "station"),
                MetricSlot(id: "temp", role: .chip, unit: "°", decimals: 1,
                           scale: .temperature, query: "station"),
                MetricSlot(id: "rh", role: .chip, unit: "%", scale: .humidity,
                           query: "station"),
                MetricSlot(id: "mslp", role: .chip, scale: .pressure, query: "station"),
            ])
    }

    static func snapshot(_ r: Windguru.StationReading, series: [Double?]) -> WindSnapshot {
        var values: [String: Double] = [:]
        values["avg"] = r.wind
        values["gust"] = r.gust
        values["dir"] = r.dir
        values["temp"] = r.temp
        values["rh"] = r.rh
        values["mslp"] = r.mslp
        return WindSnapshot(values: values, series: series, measuredAt: r.at)
    }
}

