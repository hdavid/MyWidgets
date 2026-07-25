import Foundation
import SwiftUI

// MARK: - Snapshot
//
// Slot-keyed rather than one field per measurement: which metrics exist is a
// user setting now (see Shared/GrafanaConfig.swift), so the snapshot can't name
// them at compile time.

struct WindSnapshot: Codable {
    /// slot id → last value
    var values: [String: Double]
    /// slot id → the same metric a while ago, for the tendency arrow
    var trends: [String: Double]
    /// the `.series` slot's values, drawn as the background sparkline
    var series: [Double?]
    var measuredAt: Date?
    var fetchedAt: Date

    init(values: [String: Double] = [:], trends: [String: Double] = [:],
         series: [Double?] = [], measuredAt: Date? = nil, fetchedAt: Date = Date()) {
        self.values = values
        self.trends = trends
        self.series = series
        self.measuredAt = measuredAt
        self.fetchedAt = fetchedAt
    }

    func value(_ slot: MetricSlot?) -> Double? {
        guard let slot else { return nil }
        return values[slot.id]
    }

    func trend(_ slot: MetricSlot?) -> Double? {
        guard let slot else { return nil }
        return trends[slot.id]
    }
}

// MARK: - Grafana client

/// One completed slot fetch, collected out of the task group below.
private enum SlotResult {
    case value(String, Double, Date)
    case trend(String, Double)
    case series([Double?])
}

enum Grafana {
    /// POST one raw InfluxQL query, return (values, timestamps-ms).
    static func query(_ q: String, _ s: GrafanaSource) async throws -> (values: [Double?], times: [Double]) {
        guard let url = s.queryURL else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(s.token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15
        let body: [String: Any] = [
            "queries": [[
                "refId": "A", "datasourceId": s.datasourceId, "rawQuery": true,
                "query": q, "resultFormat": "time_series"
            ] as [String: Any]],
            "from": s.window, "to": "now"
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        guard
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let results = obj["results"] as? [String: Any],
            let a = results["A"] as? [String: Any],
            let frames = a["frames"] as? [[String: Any]],
            let frame = frames.first,
            let d = frame["data"] as? [String: Any],
            let values = d["values"] as? [[Any]],
            values.count >= 2
        else { throw URLError(.cannotParseResponse) }

        let times = values[0].compactMap { ($0 as? NSNumber)?.doubleValue }
        let vals = values[1].map { ($0 as? NSNumber)?.doubleValue }
        return (vals, times)
    }

    static func lastValue(_ q: String, _ s: GrafanaSource) async -> (value: Double, at: Date)? {
        guard let (vals, times) = try? await query(q, s),
              let v = vals.first ?? nil else { return nil }
        let at = times.first.map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()
        return (v, at)
    }

    /// Fetch every enabled slot concurrently. Returns nil when nothing came
    /// back at all, so the caller can fall back to the last good snapshot.
    static func fetchAll(_ s: GrafanaSource) async -> WindSnapshot? {
        guard s.isConfigured else { return nil }
        let slots = s.slots.filter { $0.enabled && !$0.query.isEmpty }
        guard !slots.isEmpty else { return nil }
        let primaryID = s.slot(.primary)?.id

        var values: [String: Double] = [:]
        var trends: [String: Double] = [:]
        var series: [Double?] = []
        var measuredAt: Date?

        await withTaskGroup(of: SlotResult?.self) { group in
            for slot in slots {
                if slot.role == .series {
                    group.addTask {
                        guard let r = try? await query(slot.query, s) else { return nil }
                        return .series(r.values)
                    }
                    continue
                }
                group.addTask {
                    guard let r = await lastValue(slot.query, s) else { return nil }
                    return .value(slot.id, r.value, r.at)
                }
                if !slot.trendQuery.isEmpty {
                    group.addTask {
                        guard let r = await lastValue(slot.trendQuery, s) else { return nil }
                        return .trend(slot.id, r.value)
                    }
                }
            }
            for await result in group {
                switch result {
                case .value(let id, let v, let at):
                    values[id] = v
                    // The headline metric's timestamp is what "measured at" means.
                    if id == primaryID || measuredAt == nil { measuredAt = at }
                case .trend(let id, let v):
                    trends[id] = v
                case .series(let vs):
                    series = vs
                case nil:
                    break
                }
            }
        }

        guard !values.isEmpty || !series.isEmpty else { return nil }
        return WindSnapshot(values: values, trends: trends, series: series,
                            measuredAt: measuredAt, fetchedAt: Date())
    }
}

// MARK: - Last-good-snapshot cache (widget extension's own defaults)

enum WindStore {
    /// Per source: several metrics widgets can be placed, each on its own
    /// Grafana source, and one must not overwrite another's last-good values.
    private static func key(_ sourceID: String) -> String { "lastSnapshot_\(sourceID)" }

    static func save(_ snap: WindSnapshot, for sourceID: String) {
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: key(sourceID))
        }
    }

    static func load(for sourceID: String) -> WindSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: key(sourceID)) else { return nil }
        return try? JSONDecoder().decode(WindSnapshot.self, from: data)
    }
}
