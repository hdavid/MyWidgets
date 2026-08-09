import Foundation

// MARK: - Tide locations
//
// A tide location is a place whose tide the tide widgets show. Its data
// source is a PORT from the bundled harmonic catalog (TidePorts): the port
// carries constituents and datum, so heights come out on the printed-table
// scale with nothing to configure. An optional linear calibration
// (heightScale/heightBias) corrects a port against maree.info — fitted for
// Pornic at h' = 0.913·h + 0.488, max residual 10 cm. `mareeInfoId` is only
// ever used to build the click-through link — maree.info's terms allow links
// but forbid automated extraction, so no data is fetched there.
//
// Legacy shape (windguruSpot + tideOffset, constituents fetched from
// windguru) still decodes and still works, so configs from before the port
// catalog keep rendering until they're edited.

/// Maps synthesized heights (cm above MSL) onto the local tide-table scale.
struct TideScale: Equatable {
    let offset: Double   // MSL → datum, metres
    let scale: Double    // calibration, 1 when uncalibrated
    let bias: Double     // calibration, 0 when uncalibrated

    func table(_ cmMSL: Double) -> Double {
        (cmMSL / 100 + offset) * scale + bias
    }

    /// Inverse, for expressing a table-scale threshold in cm above MSL.
    func cmMSL(fromTable h: Double) -> Double {
        ((h - bias) / scale - offset) * 100
    }
}

struct TideLocation: Codable, Identifiable, Equatable {
    var id: String
    /// Widget heading, e.g. "Les Moutiers".
    var title: String
    /// Catalog port name (e.g. "PORNIC, France") — the tide data source.
    var port: String?
    /// Calibration against maree.info; nil means uncorrected.
    var heightScale: Double?
    var heightBias: Double?
    /// maree.info port number for the click-through page (119 = Pornic).
    var mareeInfoId: Int
    /// Thresholds in table metres, one line drawn per value. The first one is
    /// the primary (shown where only one fits).
    var thresholds: [Double]
    /// Whether the watch app shows this entry as a page.
    var watch: Bool?
    // Legacy source: windguru constituents + manual offset.
    var windguruSpot: Int?
    var tideOffset: Double?

    var onWatch: Bool { watch ?? true }

    var pageURL: URL? { URL(string: "https://maree.info/\(mareeInfoId)") }

    /// The height mapping for this location's source; nil when neither a
    /// known port nor a legacy offset is configured.
    var heightMapping: TideScale? {
        if let p = TidePorts.port(port) {
            return TideScale(offset: p.datum, scale: heightScale ?? 1, bias: heightBias ?? 0)
        }
        if let tideOffset {
            return TideScale(offset: tideOffset, scale: heightScale ?? 1, bias: heightBias ?? 0)
        }
        return nil
    }

    init(id: String, title: String, port: String? = nil,
         heightScale: Double? = nil, heightBias: Double? = nil,
         mareeInfoId: Int, thresholds: [Double],
         windguruSpot: Int? = nil, tideOffset: Double? = nil) {
        self.id = id
        self.title = title
        self.port = port
        self.heightScale = heightScale
        self.heightBias = heightBias
        self.mareeInfoId = mareeInfoId
        self.thresholds = thresholds
        self.windguruSpot = windguruSpot
        self.tideOffset = tideOffset
    }

    // Accept the original single-`threshold` shape so early tide.json files
    // and exports keep decoding.
    private enum CodingKeys: String, CodingKey {
        case id, title, port, heightScale, heightBias, mareeInfoId
        case thresholds, threshold, watch, windguruSpot, tideOffset
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        port = try c.decodeIfPresent(String.self, forKey: .port)
        heightScale = try c.decodeIfPresent(Double.self, forKey: .heightScale)
        heightBias = try c.decodeIfPresent(Double.self, forKey: .heightBias)
        mareeInfoId = try c.decode(Int.self, forKey: .mareeInfoId)
        watch = try c.decodeIfPresent(Bool.self, forKey: .watch)
        windguruSpot = try c.decodeIfPresent(Int.self, forKey: .windguruSpot)
        tideOffset = try c.decodeIfPresent(Double.self, forKey: .tideOffset)
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
        try c.encodeIfPresent(port, forKey: .port)
        try c.encodeIfPresent(heightScale, forKey: .heightScale)
        try c.encodeIfPresent(heightBias, forKey: .heightBias)
        try c.encode(mareeInfoId, forKey: .mareeInfoId)
        try c.encode(thresholds, forKey: .thresholds)
        try c.encodeIfPresent(watch, forKey: .watch)
        try c.encodeIfPresent(windguruSpot, forKey: .windguruSpot)
        try c.encodeIfPresent(tideOffset, forKey: .tideOffset)
    }
}

enum TideConfig {
    static let fileName = "tide.json"

    static var fileURL: URL? { ConfigStore.url(fileName) }

    /// Pornic's calibration (fitted on maree.info's table, 2026-08-09).
    static let defaultLocations = [
        TideLocation(id: "moutiers", title: "Les Moutiers", port: "PORNIC, France",
                     heightScale: 0.913, heightBias: 0.488,
                     mareeInfoId: 119, thresholds: [3.8]),
        TideLocation(id: "bernerie", title: "La Bernerie", port: "PORNIC, France",
                     heightScale: 0.913, heightBias: 0.488,
                     mareeInfoId: 119, thresholds: [3.5]),
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
