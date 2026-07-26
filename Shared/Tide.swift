import Foundation

// MARK: - Tide from harmonic constituents
//
// Windguru doesn't serve a tide curve — `q=spot` hands out the spot's harmonic
// constituents (amplitude in cm above MSL, Greenwich phase lag in degrees) and
// its own page synthesises the curve in the browser. Doing the same here means
// the tide row needs no second service, no key, and no network at all once the
// constituents are cached: they are a property of the place, not a forecast.
//
// Accuracy, checked against the high/low extremes windguru prints under its own
// table for spot 67620 over three days: height RMS 2.4 cm (max 3 cm) on a 3.5 m
// range, time RMS 1.7 min (max 3 min).

/// One spot's tide, exactly as `q=spot` returns it.
struct TideHarmonics: Codable, Equatable {
    /// Constituent name → (amplitude cm, Greenwich phase lag degrees).
    var constituents: [String: [Double]]
    /// Named levels in cm above MSL: mhhw, mllw, hat, lat…
    var datums: [String: Double]

    var isUsable: Bool { !constituents.isEmpty }

    /// The band the widget scales its bars against — mean higher high to mean
    /// lower low, so a neap day visibly falls short of a spring day instead of
    /// every day being redrawn full-height. Falls back to the astronomical
    /// extremes, then to a plain ±2 m, for spots with a sparser datum list.
    var displayRange: (low: Double, high: Double) {
        let high = datums["mhhw"] ?? datums["mhw"] ?? datums["hat"] ?? 200
        let low = datums["mllw"] ?? datums["mlw"] ?? datums["lat"] ?? -200
        return high > low ? (low, high) : (-200, 200)
    }
}

enum Tide {
    // MARK: Constituent table

    /// Doodson coefficients in the τ basis — [τ, s, h, p, N, p₁] — plus the
    /// constituent's fixed phase offset and which nodal correction it follows.
    ///
    /// τ is mean lunar time, s the moon's mean longitude, h the sun's, p the
    /// lunar perigee, N the ascending node, p₁ the solar perigee. Speeds fall
    /// out of the coefficients, so there is no separate table of them to keep
    /// in step.
    private struct Constituent {
        let n: [Double]      // [τ, s, h, p, N, p₁]
        let offset: Double   // degrees
        let nodal: Nodal
    }

    private enum Nodal { case none, m2, k1, o1, k2, j1, mm, mf, m3, m4, m6, m8 }

    /// The 34 constituents windguru publishes.
    ///
    /// The diurnal offsets are the sign convention windguru's phases are
    /// expressed in, which is the opposite of Schureman's for this species:
    /// with Schureman's signs the semidiurnal part still lands within 5 min but
    /// the diurnal inequality inverts, alternating ±24 cm between consecutive
    /// high waters (height RMS 15.7 cm against windguru's own figures, versus
    /// 2.4 cm for the signs below). Determined by fitting, not assumed.
    private static let table: [String: Constituent] = [
        "M2":      .init(n: [2,  0,  0,  0, 0, 0], offset:    0, nodal: .m2),
        "S2":      .init(n: [2,  2, -2,  0, 0, 0], offset:    0, nodal: .none),
        "N2":      .init(n: [2, -1,  0,  1, 0, 0], offset:    0, nodal: .m2),
        "K2":      .init(n: [2,  2,  0,  0, 0, 0], offset:    0, nodal: .k2),
        "K1":      .init(n: [1,  1,  0,  0, 0, 0], offset:   90, nodal: .k1),
        "O1":      .init(n: [1, -1,  0,  0, 0, 0], offset:  -90, nodal: .o1),
        "P1":      .init(n: [1,  1, -2,  0, 0, 0], offset:  -90, nodal: .none),
        "Q1":      .init(n: [1, -2,  0,  1, 0, 0], offset:  -90, nodal: .o1),
        "J1":      .init(n: [1,  2,  0, -1, 0, 0], offset:   90, nodal: .j1),
        "S1":      .init(n: [1,  1, -1,  0, 0, 0], offset:  180, nodal: .none),
        "2N2":     .init(n: [2, -2,  0,  2, 0, 0], offset:    0, nodal: .m2),
        "MU2":     .init(n: [2, -2,  2,  0, 0, 0], offset:    0, nodal: .m2),
        "NU2":     .init(n: [2, -1,  2, -1, 0, 0], offset:    0, nodal: .m2),
        "L2":      .init(n: [2,  1,  0, -1, 0, 0], offset:  180, nodal: .m2),
        "LAMBDA2": .init(n: [2,  1, -2,  1, 0, 0], offset:  180, nodal: .m2),
        "T2":      .init(n: [2,  2, -3,  0, 0, 1], offset:    0, nodal: .none),
        "R2":      .init(n: [2,  2, -1,  0, 0,-1], offset:  180, nodal: .none),
        "EPS2":    .init(n: [2, -3,  2,  1, 0, 0], offset:    0, nodal: .m2),
        "MKS2":    .init(n: [2,  0,  2,  0, 0, 0], offset:    0, nodal: .m2),
        "M3":      .init(n: [3,  0,  0,  0, 0, 0], offset:    0, nodal: .m3),
        "M4":      .init(n: [4,  0,  0,  0, 0, 0], offset:    0, nodal: .m4),
        "M6":      .init(n: [6,  0,  0,  0, 0, 0], offset:    0, nodal: .m6),
        "M8":      .init(n: [8,  0,  0,  0, 0, 0], offset:    0, nodal: .m8),
        "MS4":     .init(n: [4,  2, -2,  0, 0, 0], offset:    0, nodal: .m2),
        "MN4":     .init(n: [4, -1,  0,  1, 0, 0], offset:    0, nodal: .m4),
        "N4":      .init(n: [4, -2,  0,  2, 0, 0], offset:    0, nodal: .m4),
        "S4":      .init(n: [4,  4, -4,  0, 0, 0], offset:    0, nodal: .none),
        "MM":      .init(n: [0,  1,  0, -1, 0, 0], offset:    0, nodal: .mm),
        "MF":      .init(n: [0,  2,  0,  0, 0, 0], offset:    0, nodal: .mf),
        "MSF":     .init(n: [0,  2, -2,  0, 0, 0], offset:    0, nodal: .none),
        "MTM":     .init(n: [0,  3,  0, -1, 0, 0], offset:    0, nodal: .mf),
        "MSQM":    .init(n: [0,  4, -2,  0, 0, 0], offset:    0, nodal: .none),
        "SA":      .init(n: [0,  0,  1,  0, 0, 0], offset:    0, nodal: .none),
        "SSA":     .init(n: [0,  0,  2,  0, 0, 0], offset:    0, nodal: .none),
    ]

    // MARK: Astronomy

    private static let deg = Double.pi / 180

    /// Mean longitudes in degrees at `date`, plus mean lunar time.
    private static func astro(_ date: Date) -> (tau: Double, s: Double, h: Double,
                                                p: Double, n: Double, p1: Double) {
        // Julian day from the Unix epoch, then centuries from J2000.0.
        let jd = date.timeIntervalSince1970 / 86400 + 2440587.5
        let t = (jd - 2451545.0) / 36525
        let s  = 218.3164477 + 481267.88123421 * t
        let h  = 280.46646   +  36000.76983    * t
        let p  =  83.3532465 +   4069.0137287  * t
        let n  = 125.0445479 -   1934.1362891  * t
        let p1 = 282.9373400 +      1.7195366  * t
        // Hours of UT, which is what mean lunar time is reckoned from — a local
        // clock here silently shifts every constituent.
        let ut = (jd + 0.5).truncatingRemainder(dividingBy: 1) * 24
        return (15 * ut + h - s, s, h, p, n, p1)
    }

    /// Doodson's approximations for the 18.6-year nodal modulation: `f` scales
    /// the amplitude, `u` (degrees) shifts the phase.
    private static func nodal(_ kind: Nodal, _ n: Double) -> (f: Double, u: Double) {
        let c1 = cos(n * deg), c2 = cos(2 * n * deg), c3 = cos(3 * n * deg)
        let s1 = sin(n * deg), s2 = sin(2 * n * deg), s3 = sin(3 * n * deg)
        let m2 = (f: 1.0004 - 0.0373 * c1 + 0.0002 * c2, u: -2.14 * s1)
        switch kind {
        case .none: return (1, 0)
        case .m2:   return m2
        case .k1:   return (1.0060 + 0.1150 * c1 - 0.0088 * c2 + 0.0006 * c3,
                            -8.86 * s1 + 0.68 * s2 - 0.07 * s3)
        case .o1:   return (1.0089 + 0.1871 * c1 - 0.0147 * c2 + 0.0014 * c3,
                            10.80 * s1 - 1.34 * s2 + 0.19 * s3)
        case .k2:   return (1.0241 + 0.2863 * c1 + 0.0083 * c2 - 0.0015 * c3,
                            -17.74 * s1 + 0.68 * s2 - 0.04 * s3)
        case .j1:   return (1.0129 + 0.1676 * c1 - 0.0170 * c2 + 0.0016 * c3,
                            -12.94 * s1 + 1.34 * s2 - 0.19 * s3)
        case .mm:   return (1.0000 - 0.1300 * c1 + 0.0013 * c2, 0)
        case .mf:   return (1.0429 + 0.4135 * c1 - 0.0040 * c2,
                            -23.74 * s1 + 2.68 * s2 - 0.38 * s3)
        // Shallow-water constituents ride on M2's modulation.
        case .m3:   return (pow(m2.f, 1.5), 1.5 * m2.u)
        case .m4:   return (m2.f * m2.f, 2 * m2.u)
        case .m6:   return (pow(m2.f, 3), 3 * m2.u)
        case .m8:   return (pow(m2.f, 4), 4 * m2.u)
        }
    }

    // MARK: Synthesis

    /// Sea level in cm above MSL at `date`.
    static func height(_ tide: TideHarmonics, at date: Date) -> Double {
        let a = astro(date)
        var sum = 0.0
        for (name, values) in tide.constituents {
            guard values.count == 2, let c = table[name] else { continue }
            let (amplitude, phase) = (values[0], values[1])
            let v = c.n[0] * a.tau + c.n[1] * a.s + c.n[2] * a.h
                  + c.n[3] * a.p + c.n[4] * a.n + c.n[5] * a.p1 + c.offset
            let (f, u) = nodal(c.nodal, a.n)
            sum += f * amplitude * cos((v + u - phase) * deg)
        }
        return sum
    }

    /// Where `date` sits in the spot's usual tidal band, 0 (low) … 1 (high).
    /// Clamped, since a spring tide overshoots the mean levels by design.
    static func level(_ tide: TideHarmonics, at date: Date) -> Double {
        level(tide, from: height(tide, at: date))
    }

    /// Same scaling for a height already in hand — the widget needs the height
    /// itself to decide the bar's colour, and synthesising it twice per cell
    /// would double the row's cost for nothing.
    static func level(_ tide: TideHarmonics, from height: Double) -> Double {
        let (low, high) = tide.displayRange
        return min(1, max(0, (height - low) / (high - low)))
    }
}

// MARK: - Cache
//
// Constituents describe the place, so they are fetched once and kept — a widget
// with no network still draws its tide row.

enum TideStore {
    private static func key(_ spotID: String) -> String { "tide_\(spotID)" }

    static func save(_ t: TideHarmonics, for spotID: String) {
        if let data = try? JSONEncoder().encode(t) {
            UserDefaults.standard.set(data, forKey: key(spotID))
        }
    }

    static func load(for spotID: String) -> TideHarmonics? {
        guard let data = UserDefaults.standard.data(forKey: key(spotID)) else { return nil }
        return try? JSONDecoder().decode(TideHarmonics.self, from: data)
    }
}
