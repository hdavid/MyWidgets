import Foundation

// MARK: - Slot roles
//
// A metrics widget's layout skeleton is fixed — rose + big value + a secondary
// line, then rows of chips. A role says which of those places a metric lands
// in; everything else about the metric (query, label, unit, scale) is the
// user's. Roles other than `.chip` fill exactly one place, so only the first
// enabled slot with that role is used.

enum SlotRole: String, Codable, CaseIterable, Identifiable {
    case primary      // the big number
    case secondary    // first item on the line under it
    case tertiary     // second item on that line
    case direction    // degrees — drives the wind rose and the header compass
    case series       // time series — drives the background sparkline
    case chip         // small colored value, laid out in rows of three

    var id: String { rawValue }

    var label: String {
        switch self {
        case .primary:   return "Big number"
        case .secondary: return "Secondary"
        case .tertiary:  return "Tertiary"
        case .direction: return "Rose (degrees)"
        case .series:    return "Sparkline"
        case .chip:      return "Chip"
        }
    }
}

// MARK: - One configurable metric

struct MetricSlot: Codable, Identifiable, Equatable {
    var id: String
    var role: SlotRole
    var label: String        // "" draws the value with no caption
    var unit: String         // appended straight after the number
    var decimals: Int
    var scale: MetricScale
    var query: String        // raw InfluxQL, exactly as Grafana receives it
    /// Optional second query read as "the value a while ago". When set, a
    /// tendency arrow (↑↗→↘↓) is appended — that's the 3 h pressure trend.
    var trendQuery: String
    var enabled: Bool

    init(id: String = UUID().uuidString,
         role: SlotRole,
         label: String = "",
         unit: String = "",
         decimals: Int = 0,
         scale: MetricScale = .none,
         query: String,
         trendQuery: String = "",
         enabled: Bool = true) {
        self.id = id
        self.role = role
        self.label = label
        self.unit = unit
        self.decimals = decimals
        self.scale = scale
        self.query = query
        self.trendQuery = trendQuery
        self.enabled = enabled
    }

    /// "Gust 12.4kn↗" — the whole thing the widget prints for this slot.
    func text(_ value: Double?, trend: Double? = nil) -> String {
        let number = fmtN(value, decimals) + unit + pressureTrend(value, trend)
        return label.isEmpty ? number : "\(label) \(number)"
    }
}

// MARK: - One Grafana source (a connection plus what to draw from it)

struct GrafanaSource: Codable, Identifiable, Equatable {
    var id: String
    var title: String          // widget heading
    var baseURL: String        // Grafana root, e.g. https://host/grafana
    var token: String          // service-account token (never stored in source)
    var datasourceId: Int
    var dashboardURL: String   // opened when the widget is clicked
    var window: String         // query time window, e.g. "now-3h"
    var slots: [MetricSlot]

    init(id: String = UUID().uuidString,
         title: String,
         baseURL: String = "",
         token: String = "",
         datasourceId: Int = 1,
         dashboardURL: String = "",
         window: String = "now-3h",
         slots: [MetricSlot] = GrafanaSource.exampleSlots()) {
        self.id = id
        self.title = title
        self.baseURL = baseURL
        self.token = token
        self.datasourceId = datasourceId
        self.dashboardURL = dashboardURL
        self.window = window
        self.slots = slots
    }

    /// The `/api/ds/query` endpoint derived from `baseURL`.
    var queryURL: URL? {
        var root = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while root.hasSuffix("/") { root.removeLast() }
        guard !root.isEmpty else { return nil }
        return URL(string: root + "/api/ds/query")
    }

    var isConfigured: Bool { queryURL != nil && !token.isEmpty }

    func slot(_ role: SlotRole) -> MetricSlot? {
        slots.first { $0.role == role && $0.enabled && !$0.query.isEmpty }
    }

    var chips: [MetricSlot] {
        slots.filter { $0.role == .chip && $0.enabled && !$0.query.isEmpty }
    }

    /// Chips wrapped into rows of three.
    var chipRows: [[MetricSlot]] {
        stride(from: 0, to: chips.count, by: 3).map {
            Array(chips[$0..<min($0 + 3, chips.count)])
        }
    }

    /// A starting point for a new source: the shape of a weather station, with
    /// placeholder measurement names to be edited.
    static func exampleSlots() -> [MetricSlot] {
        [
            MetricSlot(role: .primary, unit: "kn", decimals: 1, scale: .wind,
                       query: "SELECT last(value) FROM autogen.wind_avg_knots"),
            MetricSlot(role: .secondary, label: "Gust", decimals: 1, scale: .wind,
                       query: "SELECT last(value) FROM autogen.wind_gust_knots"),
            MetricSlot(role: .direction, unit: "°", decimals: 0,
                       query: "SELECT last(value) FROM autogen.wind_direction_deg"),
            MetricSlot(role: .series,
                       query: "SELECT mean(value) FROM autogen.wind_avg_knots WHERE time > now() - 1h GROUP BY time(1m) fill(none)"),
            MetricSlot(role: .chip, unit: "°", decimals: 1, scale: .temperature,
                       query: "SELECT last(value) FROM autogen.temperature_c"),
        ]
    }
}

// MARK: - The configured sources

enum GrafanaConfig {
    static let fileName = "grafana.json"

    static var fileURL: URL? { ConfigStore.url(fileName) }

    /// Deliberately generic: real endpoints belong in the App Group config (see
    /// scripts/local-config.sh), not committed to the repo.
    static let defaultSources = [
        GrafanaSource(id: "default", title: "Weather station")
    ]

    static func load() -> [GrafanaSource] {
        guard let data = ConfigStore.read(fileName),
              let sources = try? JSONDecoder().decode([GrafanaSource].self, from: data),
              !sources.isEmpty
        else { return defaultSources }
        return sources
    }

    /// The source a widget instance is bound to, falling back to the first one
    /// so a widget placed before anything was configured still shows something.
    static func source(_ id: String?) -> GrafanaSource? {
        let all = load()
        guard let id else { return all.first }
        return all.first { $0.id == id } ?? all.first
    }

    @discardableResult
    static func save(_ sources: [GrafanaSource]) -> Bool {
        guard let url = ConfigStore.writeURL(fileName) else { return false }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(sources) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}
