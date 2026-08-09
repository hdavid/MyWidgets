import Foundation

// MARK: - Tide extremes and the French coefficient
//
// Everything here is synthesized locally from cached harmonic constituents
// (Tide.swift) — no network after the constituents are cached, and nothing is
// ever fetched from maree.info.
//
// The coefficient is computed the way SHOM defines it: from the semi-diurnal
// tide at BREST. Synthesizing Brest's four main semi-diurnal constituents
// (M2 S2 N2 K2) and scaling each high water by the unit of height U = 3.05 m
// tracks maree.info's published table with a constant bias; subtracting the
// fitted bias lands within ±1 across the whole 48…103 range checked on
// 2026-08-09..15. Verified against the same table: Pornic times within
// ±15 min, low heights within ±5 cm (highs read ~0.2 m above the Pornic
// table — the constituents describe Les Moutiers, one bay south).

struct TideExtreme: Equatable {
    let date: Date
    /// Metres on the local printed-table scale (MSL + tideOffset).
    let height: Double
    let isHigh: Bool
    /// French tidal coefficient (20…120), high waters only.
    var coefficient: Int?
}

enum TideModel {

    /// Windguru spot for Brest, France — the coefficient's reference port
    /// (M2 ≈ 2.19 m; probed 2026-08-09, spots named "Brest" elsewhere exist).
    static let brestSpot = 3040
    private static let brestCacheKey = "brest\(brestSpot)"

    /// Unit of height at Brest (SHOM), metres.
    private static let brestUnit = 3.05
    /// Constant bias between our SD4 synthesis and maree.info's table,
    /// fitted over 13 consecutive tides (σ = 0.35).
    private static let coefficientBias = 7.15

    // MARK: Constituents cache

    /// Local + Brest constituents, fetching whichever is missing. Returns nil
    /// for the local set only if it was never cached and the network failed.
    static func harmonics(for location: TideLocation) async
        -> (local: TideHarmonics?, brest: TideHarmonics?) {
        async let local = cached(spot: location.windguruSpot, key: String(location.windguruSpot))
        async let brest = cached(spot: brestSpot, key: brestCacheKey)
        return await (local, brest)
    }

    private static func cached(spot: Int, key: String) async -> TideHarmonics? {
        if let t = TideStore.load(for: key), t.isUsable { return t }
        guard let t = await Windguru.spotInfo(spot: spot)?.tide, t.isUsable else { return nil }
        TideStore.save(t, for: key)
        return t
    }

    // MARK: Extremes

    /// High/low waters in `range`, on the table scale, coefficients attached
    /// to the highs when Brest constituents are in hand.
    static func extremes(_ tide: TideHarmonics, offset: Double, brest: TideHarmonics?,
                         in range: ClosedRange<Date>) -> [TideExtreme] {
        var out = rawExtremes(of: { Tide.height(tide, at: $0) }, in: range).map {
            TideExtreme(date: $0.date, height: $0.value / 100 + offset, isHigh: $0.isHigh)
        }
        guard let brest else { return out }

        // Brest's high waters run ~35 min ahead of Pornic's; a ±4 h pairing
        // window is far tighter than the ~12.4 h tide interval.
        let sd4 = TideHarmonics(
            constituents: brest.constituents.filter { ["M2", "S2", "N2", "K2"].contains($0.key) },
            datums: [:])
        let padded = range.lowerBound.addingTimeInterval(-4 * 3600)
            ... range.upperBound.addingTimeInterval(4 * 3600)
        let brestHighs = rawExtremes(of: { Tide.height(sd4, at: $0) }, in: padded)
            .filter { $0.isHigh }
        for i in out.indices where out[i].isHigh {
            guard let match = brestHighs.min(by: {
                abs($0.date.timeIntervalSince(out[i].date)) < abs($1.date.timeIntervalSince(out[i].date))
            }), abs(match.date.timeIntervalSince(out[i].date)) < 4 * 3600 else { continue }
            let c = (100 * (match.value / 100) / brestUnit - coefficientBias).rounded()
            out[i].coefficient = Int(min(120, max(20, c)))
        }
        return out
    }

    /// Extremes of an arbitrary height function by 5-minute sampling with
    /// parabolic refinement — the curve is smooth, so this lands within
    /// seconds of the true extremum.
    private static func rawExtremes(of height: (Date) -> Double, in range: ClosedRange<Date>)
        -> [(date: Date, value: Double, isHigh: Bool)] {
        let step = 300.0
        let n = Int(range.upperBound.timeIntervalSince(range.lowerBound) / step)
        guard n > 2 else { return [] }
        let h = (0...n).map { height(range.lowerBound.addingTimeInterval(Double($0) * step)) }
        var out: [(Date, Double, Bool)] = []
        for i in 1..<n where (h[i] - h[i-1]) * (h[i+1] - h[i]) <= 0 && h[i-1] != h[i] {
            let d1 = h[i] - h[i-1], d2 = h[i+1] - h[i]
            let off = d1 - d2 != 0 ? 0.5 * (d1 + d2) / (d1 - d2) * step : 0
            let t = range.lowerBound.addingTimeInterval(Double(i) * step + off)
            out.append((t, height(t), h[i] > h[i-1]))
        }
        return out
    }

    // MARK: Instant status (complications)

    /// Everything a complication needs about one instant, precomputed so the
    /// view is pure drawing.
    struct Status {
        let date: Date
        /// Table-scale metres.
        let height: Double
        let rising: Bool
        /// 0 at high water, 0.5 at low, back to 1 at the next high — the
        /// needle turns clockwise from 12 o'clock like a tide clock.
        let phase: Double
        /// Coefficient of the current tide (its high water's).
        let coefficient: Int?
        let previous: TideExtreme
        let next: TideExtreme
        /// All configured thresholds (for the dial's chords, whether or not
        /// they get crossed soon).
        let thresholds: [Double]
        /// Next crossing of each configured threshold within 24 h, in
        /// threshold order; `rising` tells which way it crosses.
        let crossings: [(threshold: Double, date: Date, rising: Bool)]

        /// The current cycle's bounds, for mapping heights onto the dial.
        var cycleLow: Double { min(previous.height, next.height) }
        var cycleHigh: Double { max(previous.height, next.height) }
    }

    static func status(_ tide: TideHarmonics, offset: Double, brest: TideHarmonics?,
                       thresholds: [Double], at date: Date) -> Status? {
        let window = date.addingTimeInterval(-15 * 3600) ... date.addingTimeInterval(15 * 3600)
        let ext = extremes(tide, offset: offset, brest: brest, in: window)
        guard let prev = ext.last(where: { $0.date <= date }),
              let next = ext.first(where: { $0.date > date }) else { return nil }
        let f = date.timeIntervalSince(prev.date) / next.date.timeIntervalSince(prev.date)
        let phase = next.isHigh ? 0.5 + f / 2 : f / 2
        // The tide's coefficient belongs to its high water — the one we're
        // falling from or rising towards.
        let coef = (next.isHigh ? next.coefficient : prev.coefficient)
            ?? (next.isHigh ? prev.coefficient : next.coefficient)
        return Status(
            date: date,
            height: Tide.height(tide, at: date) / 100 + offset,
            rising: next.isHigh,
            phase: phase,
            coefficient: coef,
            previous: prev,
            next: next,
            thresholds: thresholds,
            crossings: thresholds.compactMap { t in
                crossing(tide, offset: offset, of: t, after: date).map { (t, $0.date, $0.rising) }
            })
    }

    /// First time `height` crosses `threshold` after `date` (within 24 h),
    /// by 5-minute sampling and linear interpolation.
    static func crossing(_ tide: TideHarmonics, offset: Double, of threshold: Double,
                         after date: Date) -> (date: Date, rising: Bool)? {
        crossings(tide, offset: offset, of: threshold,
                  in: date...date.addingTimeInterval(24 * 3600)).first
            .map { ($0.date, $0.rising) }
    }

    /// Every crossing of `threshold` inside `range` — the widget chart labels
    /// each one on the threshold line.
    static func crossings(_ tide: TideHarmonics, offset: Double, of threshold: Double,
                          in range: ClosedRange<Date>)
        -> [(threshold: Double, date: Date, rising: Bool)] {
        let step = 300.0
        let n = Int(range.upperBound.timeIntervalSince(range.lowerBound) / step)
        guard n > 1 else { return [] }
        var out: [(Double, Date, Bool)] = []
        var prev = Tide.height(tide, at: range.lowerBound) / 100 + offset - threshold
        for i in 1...n {
            let t = range.lowerBound.addingTimeInterval(Double(i) * step)
            let cur = Tide.height(tide, at: t) / 100 + offset - threshold
            if prev != 0, (prev < 0) != (cur < 0) {
                let f = abs(prev) / (abs(prev) + abs(cur))
                out.append((threshold, t.addingTimeInterval((f - 1) * step), cur > prev))
            }
            prev = cur
        }
        return out
    }

    // MARK: Curve

    /// Table-scale heights sampled every `step` seconds across `range`,
    /// for the widget's Canvas.
    static func curve(_ tide: TideHarmonics, offset: Double,
                      in range: ClosedRange<Date>, step: TimeInterval = 600) -> [Double] {
        let n = Int(range.upperBound.timeIntervalSince(range.lowerBound) / step)
        return (0...max(1, n)).map {
            Tide.height(tide, at: range.lowerBound.addingTimeInterval(Double($0) * step)) / 100 + offset
        }
    }
}
