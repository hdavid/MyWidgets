import Foundation

// MARK: - Tide locations
//
// A tide location is a place whose tide the tide widgets show: harmonic
// constituents come from a windguru spot (fetched once, cached — see
// Tide.swift), heights are converted to the local printed-table scale with
// `tideOffset`, and `threshold` draws the "enough water" line. `mareeInfoId`
// is only ever used to build the click-through link — maree.info's terms
// allow links but forbid automated extraction, so no data is fetched there.

struct TideLocation: Codable, Identifiable, Equatable {
    var id: String
    /// Widget heading, e.g. "Les Moutiers".
    var title: String
    /// Windguru spot whose `q=spot` constituents describe this water.
    var windguruSpot: Int
    /// maree.info port number for the click-through page (119 = Pornic).
    var mareeInfoId: Int
    /// Metres to add to MSL-relative heights to match the printed tide table
    /// (same convention as WindguruSpot.tideOffset).
    var tideOffset: Double
    /// Thresholds in table metres, one line drawn per value. The first one is
    /// the primary (shown where only one fits).
    var thresholds: [Double]
    /// Whether the watch app shows this entry as a page. Optional so configs
    /// from before the toggle still decode; missing means shown.
    var watch: Bool?

    var onWatch: Bool { watch ?? true }

    var pageURL: URL? { URL(string: "https://maree.info/\(mareeInfoId)") }

    init(id: String, title: String, windguruSpot: Int, mareeInfoId: Int,
         tideOffset: Double, thresholds: [Double]) {
        self.id = id
        self.title = title
        self.windguruSpot = windguruSpot
        self.mareeInfoId = mareeInfoId
        self.tideOffset = tideOffset
        self.thresholds = thresholds
    }

    // Accept the original single-`threshold` shape so existing tide.json
    // files and exports keep decoding.
    private enum CodingKeys: String, CodingKey {
        case id, title, windguruSpot, mareeInfoId, tideOffset, thresholds, threshold, watch
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        windguruSpot = try c.decode(Int.self, forKey: .windguruSpot)
        mareeInfoId = try c.decode(Int.self, forKey: .mareeInfoId)
        tideOffset = try c.decode(Double.self, forKey: .tideOffset)
        watch = try c.decodeIfPresent(Bool.self, forKey: .watch)
        if let many = try c.decodeIfPresent([Double].self, forKey: .thresholds) {
            thresholds = many
        } else if let one = try c.decodeIfPresent(Double.self, forKey: .threshold) {
            thresholds = [one]
        } else {
            thresholds = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(windguruSpot, forKey: .windguruSpot)
        try c.encode(mareeInfoId, forKey: .mareeInfoId)
        try c.encode(tideOffset, forKey: .tideOffset)
        try c.encode(thresholds, forKey: .thresholds)
        try c.encodeIfPresent(watch, forKey: .watch)
    }
}

enum TideConfig {
    static let fileName = "tide.json"

    static var fileURL: URL? { ConfigStore.url(fileName) }

    /// Both spots sit on the same water (maree.info port Pornic); only the
    /// usable-depth threshold differs between the two beaches.
    static let defaultLocations = [
        TideLocation(id: "moutiers", title: "Les Moutiers", windguruSpot: 67620,
                     mareeInfoId: 119, tideOffset: 3.78, thresholds: [3.8]),
        TideLocation(id: "bernerie", title: "La Bernerie", windguruSpot: 67620,
                     mareeInfoId: 119, tideOffset: 3.78, thresholds: [3.5]),
    ]

    static func load() -> [TideLocation] {
        guard let data = ConfigStore.read(fileName),
              let locations = try? JSONDecoder().decode([TideLocation].self, from: data),
              !locations.isEmpty
        else { return defaultLocations }
        return locations
    }

    /// The location a widget instance is bound to, falling back to the first
    /// one so a widget placed before anything was configured still works.
    static func location(_ id: String?) -> TideLocation? {
        let all = load()
        guard let id else { return all.first }
        return all.first { $0.id == id } ?? all.first
    }

    @discardableResult
    static func save(_ locations: [TideLocation]) -> Bool {
        guard let url = ConfigStore.writeURL(fileName) else { return false }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(locations) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}
