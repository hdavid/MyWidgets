import Foundation

// MARK: - Model catalog
//
// Every named single model is fetchable on the public iapi endpoint — no login.
// The blended "WG" (wgmix, id 100) is intentionally absent: windguru computes it
// in the browser by mixing the models below, so there is no server dataset for
// it and no token can fetch it. Wind values come back in knots, matching the
// windColor scale the metrics widget uses.
//
// Which models a given spot actually offers varies by region — ask the spot with
// `q=spot` (see `Windguru.spotModels`) rather than assuming. IDs and names below
// were read from a spot's model list (tab order) plus a per-model probe; the
// order here is highest-resolution first.

struct WindguruModel: Identifiable, Hashable {
    let id: Int          // id_model
    let name: String
    let wave: Bool       // wave-only model (no wind) — hidden from the wind picker
}

enum WindguruCatalog {
    /// Known single models, keyed by id_model. Wave-only models are flagged so
    /// the wind picker can drop them.
    static let all: [WindguruModel] = [
        .init(id: 52,  name: "AROME-FR 1.3 km", wave: false),
        .init(id: 121, name: "WRF 1.5 km",      wave: false),
        .init(id: 109, name: "HARM-DK 2 km",    wave: false),
        .init(id: 101, name: "UKV 2 km",        wave: false),
        .init(id: 64,  name: "Zephr-HD 2.6 km", wave: false),
        .init(id: 57,  name: "HARMONIE 5 km",   wave: false),
        .init(id: 43,  name: "ICON 7 km",       wave: false),
        .init(id: 117, name: "IFS-HRES 9 km",   wave: false),
        .init(id: 21,  name: "WRF 9 km",        wave: false),
        .init(id: 3,   name: "GFS 13 km",       wave: false),
        .init(id: 45,  name: "ICON 13 km",      wave: false),
        .init(id: 59,  name: "GDPS 15 km",      wave: false),
        .init(id: 60,  name: "GDWPS 25 km",     wave: false),
        // Wave-only (no wind data) — hidden from the wind picker.
        .init(id: 84,  name: "GFS-Wave 16 km",  wave: true),
        .init(id: 118, name: "IFS-WAM 9 km",    wave: true),
        .init(id: 46,  name: "EWAM 5 km",       wave: true),
    ]

    static func model(_ id: Int) -> WindguruModel? { all.first { $0.id == id } }

    /// Wind models the given spot exposes (falls back to the full wind list),
    /// in the catalog's high-res-first order.
    static func windModels(available ids: [Int]?) -> [WindguruModel] {
        let wind = all.filter { !$0.wave }
        guard let ids else { return wind }
        let set = Set(ids)
        let filtered = wind.filter { set.contains($0.id) }
        return filtered.isEmpty ? wind : filtered
    }
}

/// Only show daylight hours (local) — the widget skips night rows.
///
/// 16 hours rather than the 08…21 this started as: the table is laid out from a
/// measured column width, and with WidgetKit's own content margins turned off
/// (see `ForecastWidget`) the row has width for 16 columns at very nearly the
/// old cell size. The two extra hours are spent at the ends of the day, where a
/// summer session actually happens.
enum WindguruDaytime {
    static let range = 7...22   // 07h … 22h inclusive
}

// MARK: - Spots (shared via the App Group container)

/// One configured windguru spot. Added and removed freely in the app's Windguru
/// tab; a placed forecast widget stores which one it shows in its own
/// configuration intent, so this list can be any length.
struct WindguruSpot: Codable, Identifiable, Equatable {
    var id: String
    /// Widget heading. Empty falls back to the spot id, since windguru's iapi
    /// doesn't return a spot name.
    var title: String
    /// 0 means "not configured yet" — the widget says so instead of fetching.
    var spotId: Int
    var idModel: Int

    // MARK: Tide, in local tide-table terms
    //
    // Windguru's tide is relative to mean sea level; printed tide tables use a
    // local chart datum, so the same instant reads (say) +1.17 m on windguru and
    // 4.92 m on maree.info. Both numbers below are on the TABLE's scale, which
    // is the one you actually plan around.

    /// Metres to add to windguru's height to land on the local table's scale.
    /// Calibrate by subtracting windguru's value from the table's at the same
    /// high or low water; do it at both, and average, because the two rarely
    /// agree exactly (a nearby reference port has a slightly wider range).
    var tideOffset: Double?
    /// Tide bars above this level, on the table's scale, are drawn green.
    /// Both this and `tideOffset` must be set for any green to appear.
    var tideGreenAbove: Double?

    /// The same threshold expressed the way the widget holds tide heights:
    /// centimetres above mean sea level. Nil when the pair isn't configured.
    var greenAboveMSL: Double? {
        guard let tideOffset, let tideGreenAbove else { return nil }
        return (tideGreenAbove - tideOffset) * 100
    }

    /// GFS 13 km is the one model available for every spot on earth, so it is
    /// the only sane default before a spot is known. Higher-resolution regional
    /// models are offered once "Load models" has asked the spot what it has.
    init(id: String = UUID().uuidString, title: String = "",
         spotId: Int = 0, idModel: Int = 3) {
        self.id = id
        self.title = title
        self.spotId = spotId
        self.idModel = idModel
    }

    var isConfigured: Bool { spotId > 0 }
    var heading: String { title.isEmpty ? "Spot \(spotId)" : title }
}

enum WindguruConfig {
    static let fileName = "windguru.json"

    static var fileURL: URL? { ConfigStore.url(fileName) }

    static let defaultSpots = [WindguruSpot(id: "default", title: "Forecast")]

    static func load() -> [WindguruSpot] {
        guard let data = ConfigStore.read(fileName) else { return defaultSpots }
        guard var spots = try? JSONDecoder().decode([WindguruSpot].self, from: data),
              !spots.isEmpty
        else { return defaultSpots }
        // Drop unknown model ids — notably the old blended "WG" (100), which
        // windguru computes in the browser and no endpoint will serve.
        for i in spots.indices where WindguruCatalog.model(spots[i].idModel) == nil {
            spots[i].idModel = 3
        }
        return spots
    }

    /// The spot a widget instance is bound to, falling back to the first one so a
    /// widget placed before anything was configured still shows something.
    static func spot(_ id: String?) -> WindguruSpot? {
        let all = load()
        guard let id else { return all.first }
        return all.first { $0.id == id } ?? all.first
    }

    @discardableResult
    static func save(_ spots: [WindguruSpot]) -> Bool {
        guard let url = ConfigStore.writeURL(fileName) else { return false }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(spots) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}

// MARK: - Forecast values

struct ForecastPoint: Codable {
    var time: Date
    var wind: Double        // knots
    var gust: Double        // knots
    var dir: Double         // degrees the wind blows FROM
    var temp: Double?       // °C
    // Optional, and not only because a model may omit them: they were added
    // after forecasts were already cached, and an Optional decodes as nil from
    // a stored payload that predates it instead of failing the whole entry.
    var cloud: Double?      // total cloud cover, %
    var rain: Double?       // precipitation, mm/h
    /// True for points that came from the longer-range fill-in model rather
    /// than the spot's chosen one.
    var tail: Bool?
}

struct WindguruForecast: Codable {
    var model: String
    var initDate: Date
    var points: [ForecastPoint]
    var fetchedAt: Date
    /// Name of the model the tail was filled from, when one was needed.
    var tailModel: String?

    /// Points from "now" onward (keeps the most recent past hour for context),
    /// restricted to daylight hours so the widget skips overnight rows.
    func upcoming(hours: Int, daytime: ClosedRange<Int>? = WindguruDaytime.range) -> [ForecastPoint] {
        let cutoff = Date().addingTimeInterval(-3600)
        let cal = Calendar.current
        return points.filter { p in
            guard p.time >= cutoff else { return false }
            guard let daytime else { return true }
            return daytime.contains(cal.component(.hour, from: p.time))
        }
        .prefix(hours).map { $0 }
    }
}

// MARK: - iapi client

enum Windguru {
    static let host = "https://www.windguru.net/int/iapi.php"
    static let referer = "https://www.windguru.cz/"

    static func pageURL(spot: Int) -> URL {
        URL(string: "https://www.windguru.cz/\(spot)")!
    }

    private static func request(_ query: String) -> URLRequest {
        var req = URLRequest(url: URL(string: "\(host)?\(query)")!)
        req.setValue(referer, forHTTPHeaderField: "Referer")   // API rejects requests without it
        req.timeoutInterval = 15
        return req
    }

    private static func num(_ arr: [Any]?, _ i: Int) -> Double? {
        guard let arr, i < arr.count else { return nil }
        return (arr[i] as? NSNumber)?.doubleValue
    }

    // MARK: Spot detail

    /// What `q=spot` is good for: the model list, and the spot's tide.
    struct SpotInfo {
        var models: [Int]
        var tide: TideHarmonics?
    }

    /// Public, no auth. Returns nil only when the request itself fails — a spot
    /// with no tide station simply has `tide == nil`.
    static func spotInfo(spot: Int) async -> SpotInfo? {
        guard
            let (data, resp) = try? await URLSession.shared.data(for: request("q=spot&id_spot=\(spot)")),
            (resp as? HTTPURLResponse)?.statusCode == 200,
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let models = (obj["models"] as? [Any])?.compactMap { ($0 as? NSNumber)?.intValue } ?? []

        // `tide` is a constituent → [amplitude cm, phase °] map; `tide_datums`
        // the named levels. Inland spots have neither.
        var tide: TideHarmonics?
        if let raw = obj["tide"] as? [String: Any] {
            let constituents = raw.compactMapValues { v -> [Double]? in
                guard let pair = v as? [Any], pair.count == 2 else { return nil }
                return pair.compactMap { ($0 as? NSNumber)?.doubleValue }
            }.filter { $0.value.count == 2 }
            let datums = (obj["tide_datums"] as? [String: Any])?
                .compactMapValues { ($0 as? NSNumber)?.doubleValue } ?? [:]
            if !constituents.isEmpty {
                tide = TideHarmonics(constituents: constituents, datums: datums)
            }
        }
        return SpotInfo(models: models, tide: tide)
    }

    /// Model ids the spot exposes, in tab order.
    static func spotModels(spot: Int) async -> [Int]? {
        await spotInfo(spot: spot)?.models
    }

    // MARK: Forecast

    private static func fetchModel(spot: Int, model: Int) async -> [String: Any]? {
        guard
            let (data, resp) = try? await URLSession.shared.data(
                for: request("q=forecast&id_model=\(model)&id_spot=\(spot)")),
            (resp as? HTTPURLResponse)?.statusCode == 200,
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let f = obj["fcst"] as? [String: Any]
        else { return nil }
        return f
    }

    private static func parse(_ f: [String: Any]) -> WindguruForecast? {
        guard
            let initstamp = (f["initstamp"] as? NSNumber)?.doubleValue,
            let hours = f["hours"] as? [Any],
            let windspd = f["WINDSPD"] as? [Any],
            let gust = f["GUST"] as? [Any],
            let winddir = f["WINDDIR"] as? [Any]
        else { return nil }
        let temp = f["TMP"] as? [Any]
        // TCDC is total cover; the LCDC/MCDC/HCDC split windguru's own table
        // stacks isn't worth three rows in a widget this dense.
        let cloud = f["TCDC"] as? [Any]
        let rain = f["APCP1"] as? [Any]
        let name = (f["model_name"] as? String) ?? "Forecast"

        var points: [ForecastPoint] = []
        for i in 0..<hours.count {
            guard let hr = num(hours, i), let w = num(windspd, i),
                  let g = num(gust, i), let d = num(winddir, i) else { continue }
            points.append(ForecastPoint(
                time: Date(timeIntervalSince1970: initstamp + hr * 3600),
                wind: w, gust: g, dir: d, temp: num(temp, i),
                cloud: num(cloud, i), rain: num(rain, i)))
        }
        guard !points.isEmpty else { return nil }
        return WindguruForecast(model: name,
                                initDate: Date(timeIntervalSince1970: initstamp),
                                points: points, fetchedAt: Date())
    }

    /// Fetch the spot's chosen model; on failure fall back to GFS, which every
    /// spot has, so the widget still shows something useful.
    static func fetch(_ s: WindguruSpot) async -> WindguruForecast? {
        guard s.isConfigured else { return nil }
        await cacheTideIfNeeded(s)
        if let f = await fetchModel(spot: s.spotId, model: s.idModel),
           let parsed = parse(f) {
            return await extended(parsed, spot: s)
        }
        guard s.idModel != WindguruFallback.model,
              let f = await fetchModel(spot: s.spotId, model: WindguruFallback.model),
              let parsed = parse(f) else { return nil }
        return parsed
    }

    /// High-resolution models are short: AROME-FR 1.3 km publishes 51 hours,
    /// which is two daylight lines and leaves the large widget's third empty.
    /// Rather than force a coarse model on the whole table, keep the chosen one
    /// for as far as it goes and fill the rest from GFS — the one model every
    /// spot has, and the longest-range at 181 hours. The header names both and
    /// the filled columns are marked, so the resolution drop is never silent.
    private static func extended(_ f: WindguruForecast, spot s: WindguruSpot) async -> WindguruForecast {
        guard let last = f.points.last?.time,
              last < Date().addingTimeInterval(WindguruSpan.wanted),
              s.idModel != WindguruFallback.model,
              let raw = await fetchModel(spot: s.spotId, model: WindguruFallback.model),
              let tail = parse(raw)
        else { return f }

        let extra = tail.points.filter { $0.time > last }.map {
            var p = $0
            p.tail = true
            return p
        }
        guard !extra.isEmpty else { return f }
        var out = f
        out.points += extra
        out.tailModel = tail.model
        return out
    }

    /// Tide constituents describe the place, not the weather, so this runs once
    /// per spot and then never touches the network again.
    private static func cacheTideIfNeeded(_ s: WindguruSpot) async {
        guard TideStore.load(for: s.id) == nil,
              let info = await spotInfo(spot: s.spotId), let tide = info.tide
        else { return }
        TideStore.save(tide, for: s.id)
    }
}

/// How far ahead the widget wants data, before it starts filling from a
/// longer-range model: four days covers the largest table with a day to spare.
enum WindguruSpan { static let wanted: TimeInterval = 4 * 24 * 3600 }

/// Model used when the configured one can't be fetched — GFS 13 km is the one
/// model every spot on earth exposes.
enum WindguruFallback { static let model = 3 }

// MARK: - Last-good-forecast cache

enum ForecastStore {
    /// Per spot: several forecast widgets can be placed, each on its own spot,
    /// and one must not overwrite another's last-good values.
    private static func key(_ spotID: String) -> String { "lastForecast_\(spotID)" }

    static func save(_ f: WindguruForecast, for spotID: String) {
        if let data = try? JSONEncoder().encode(f) {
            UserDefaults.standard.set(data, forKey: key(spotID))
        }
    }

    static func load(for spotID: String) -> WindguruForecast? {
        guard let data = UserDefaults.standard.data(forKey: key(spotID)) else { return nil }
        return try? JSONDecoder().decode(WindguruForecast.self, from: data)
    }
}

// MARK: - Formatting helper

/// Short hour label, e.g. "14h"; prefixes the weekday when it isn't today.
func forecastHourLabel(_ d: Date) -> String {
    let f = DateFormatter()
    if Calendar.current.isDateInToday(d) {
        f.dateFormat = "H'h'"
    } else {
        f.dateFormat = "EEE H'h'"
        f.locale = Locale(identifier: "en_US_POSIX")
    }
    return f.string(from: d)
}
