import Foundation

// MARK: - Model catalog
//
// Every named single model is fetchable on the public iapi endpoint — no login.
// The blended "WG" (wgmix, id 100) is intentionally absent: windguru computes it
// in the browser by mixing the models below, so there is no server dataset for
// it and no token can fetch it. AROME-FR 1.3 km is the highest-resolution model
// here (and the dominant near-term component of WG). Wind values come back in
// knots for spot 67620, matching the windColor scale the live-wind widget uses.
// IDs/names were verified against spot 67620's `q=spot` model list (tab order)
// plus a per-model probe.

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
enum WindguruDaytime {
    static let range = 8...21   // 08h … 21h inclusive
}

// MARK: - Settings (shared via the App Group container)

struct WindguruSettings: Codable, Equatable {
    var spotId: Int = 67620
    var idModel: Int = 52          // AROME-FR 1.3 km — best model for this spot

    static let `default` = WindguruSettings()
}

enum WindguruConfig {
    static let fileName = "windguru.json"

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroup)?
            .appendingPathComponent(fileName)
    }

    static func load() -> WindguruSettings {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              var s = try? JSONDecoder().decode(WindguruSettings.self, from: data)
        else { return .default }
        // Migrate away from the old blended "WG" id (100), which isn't fetchable.
        if WindguruCatalog.model(s.idModel) == nil { s.idModel = 52 }
        return s
    }

    @discardableResult
    static func save(_ s: WindguruSettings) -> Bool {
        guard let url = fileURL else { return false }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(s) else { return false }
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
}

struct WindguruForecast: Codable {
    var model: String
    var initDate: Date
    var points: [ForecastPoint]
    var fetchedAt: Date

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

    // MARK: Spot model list

    /// Model ids the spot exposes, in tab order (public, no auth).
    static func spotModels(spot: Int) async -> [Int]? {
        guard
            let (data, resp) = try? await URLSession.shared.data(for: request("q=spot&id_spot=\(spot)")),
            (resp as? HTTPURLResponse)?.statusCode == 200,
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let models = obj["models"] as? [Any]
        else { return nil }
        return models.compactMap { ($0 as? NSNumber)?.intValue }
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
        let name = (f["model_name"] as? String) ?? "Forecast"

        var points: [ForecastPoint] = []
        for i in 0..<hours.count {
            guard let hr = num(hours, i), let w = num(windspd, i),
                  let g = num(gust, i), let d = num(winddir, i) else { continue }
            points.append(ForecastPoint(
                time: Date(timeIntervalSince1970: initstamp + hr * 3600),
                wind: w, gust: g, dir: d, temp: num(temp, i)))
        }
        guard !points.isEmpty else { return nil }
        return WindguruForecast(model: name,
                                initDate: Date(timeIntervalSince1970: initstamp),
                                points: points, fetchedAt: Date())
    }

    /// Fetch the configured model; on failure fall back to AROME-FR 1.3 km so
    /// the widget still shows something useful.
    static func fetch(_ s: WindguruSettings) async -> WindguruForecast? {
        if let f = await fetchModel(spot: s.spotId, model: s.idModel),
           let parsed = parse(f) {
            return parsed
        }
        guard s.idModel != WindguruFallback.model,
              let f = await fetchModel(spot: s.spotId, model: WindguruFallback.model),
              let parsed = parse(f) else { return nil }
        return parsed
    }
}

/// Model used when the configured one can't be fetched.
enum WindguruFallback { static let model = 52 } // AROME-FR 1.3 km

// MARK: - Last-good-forecast cache

enum ForecastStore {
    private static let key = "lastForecast"

    static func save(_ f: WindguruForecast) {
        if let data = try? JSONEncoder().encode(f) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func load() -> WindguruForecast? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
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
