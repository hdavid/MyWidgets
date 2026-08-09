import Foundation

// MARK: - Tide port catalog
//
// data/tideports.json, extracted offline from the OpenCPN/XTide harmonic
// files (V10 HARMONIC for Europe/France + HARMONICS_NO_US worldwide) by
// scripts in the repo's history. Phases are pre-converted to the Greenwich
// convention Tide.swift synthesizes with, validated against maree.info for
// Pornic (times within ±19 min over 12 consecutive extremes). Each port
// carries its own datum, so heights land on the local tide-table scale with
// no manual offset. Bundled via BundledConfig into every target.

struct TidePort: Codable {
    /// Time meridian in hours (kept for reference; phases are Greenwich).
    var meridian: Double
    /// Metres from mean sea level to the printed-table datum.
    var datum: Double
    /// Constituent name → [amplitude cm, Greenwich phase °] — exactly the
    /// shape TideHarmonics wants.
    var constituents: [String: [Double]]
    var lon: Double?
    var lat: Double?

    var harmonics: TideHarmonics {
        TideHarmonics(constituents: constituents, datums: [:])
    }
}

enum TidePorts {
    /// The whole catalog, decoded once per process (598 KB, ~1500 ports).
    static let all: [String: TidePort] = {
        guard let data = ConfigStore.read("tideports.json"),
              let ports = try? JSONDecoder().decode([String: TidePort].self, from: data)
        else { return [:] }
        return ports
    }()

    static func port(_ name: String?) -> TidePort? {
        guard let name else { return nil }
        return all[name]
    }

    /// Brest's constituents for the French coefficient — the windguru set
    /// (bias −7.15 lands within ±1 of maree.info), bundled so a fresh install
    /// computes coefficients with no network.
    static let brest: TideHarmonics? = {
        guard let data = ConfigStore.read("tidebrest.json"),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = obj["tide"] as? [String: Any]
        else { return nil }
        let constituents = raw.compactMapValues { v -> [Double]? in
            guard let pair = v as? [Any], pair.count == 2 else { return nil }
            return pair.compactMap { ($0 as? NSNumber)?.doubleValue }
        }
        return constituents.isEmpty ? nil : TideHarmonics(constituents: constituents, datums: [:])
    }()

    /// Port names sorted for the picker: by distance when a reference point
    /// is known, alphabetically otherwise. `matching` filters by substring.
    static func names(matching query: String, near: (lon: Double, lat: Double)?) -> [String] {
        var names = Array(all.keys)
        if !query.isEmpty {
            names = names.filter { $0.localizedCaseInsensitiveContains(query) }
        }
        guard let near else { return names.sorted() }
        func d2(_ p: TidePort) -> Double {
            guard let lon = p.lon, let lat = p.lat else { return .infinity }
            let dx = (lon - near.lon) * cos(near.lat * .pi / 180)
            let dy = lat - near.lat
            return dx * dx + dy * dy
        }
        return names.sorted { d2(all[$0]!) < d2(all[$1]!) }
    }
}
