import Foundation

// MARK: - Calibration against maree.info
//
// One user-initiated fetch of the location's maree.info page (the same page
// the widget click opens), parsing the 7-day tide table a visitor sees, then
// a least-squares fit of h' = a·h + b between the port's raw synthesis and
// the table. Explicitly manual — a button press, never scheduled — so usage
// stays within "consultation", and the result is stored so it never needs
// repeating.

enum TideCalibration {

    struct Fit {
        let scale: Double
        let bias: Double
        let maxResidual: Double
        let samples: Int
    }

    enum CalibrationError: LocalizedError {
        case noPort, fetchFailed, parseFailed, tooFewPairs(Int)

        var errorDescription: String? {
            switch self {
            case .noPort: return "Pick a port first."
            case .fetchFailed: return "Could not load maree.info."
            case .parseFailed: return "Could not read the tide table."
            case .tooFewPairs(let n): return "Only \(n) extremes matched — not enough to fit."
            }
        }
    }

    static func calibrate(_ location: TideLocation) async throws -> Fit {
        guard let port = TidePorts.port(location.port) else { throw CalibrationError.noPort }
        guard let base = location.pageURL else { throw CalibrationError.fetchFailed }

        // One view of the page a click opens: 7 days ≈ 27 extremes. A week
        // spans most of a spring/neap arc, which conditions the fit well; the
        // site serves only the current week, so more isn't available anyway.
        var req = URLRequest(url: base)
        req.timeoutInterval = 20
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
                     forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let html = String(data: data, encoding: .utf8)
        else { throw CalibrationError.fetchFailed }
        let table = try parse(html)
        guard table.count >= 8 else { throw CalibrationError.parseFailed }

        // Synthesize the port's raw extremes (datum only, no correction) over
        // the table's span, then pair by time proximity.
        let raw = TideScale(offset: port.datum, scale: 1, bias: 0)
        let dates = table.map(\.date)
        guard let first = dates.min(), let last = dates.max() else {
            throw CalibrationError.parseFailed
        }
        let span = first.addingTimeInterval(-6 * 3600) ... last.addingTimeInterval(6 * 3600)
        let synth = TideModel.extremes(port.harmonics, mapping: raw, brest: nil, in: span)

        var pairs: [(mine: Double, ref: Double)] = []
        for entry in table {
            guard let match = synth.min(by: {
                abs($0.date.timeIntervalSince(entry.date)) < abs($1.date.timeIntervalSince(entry.date))
            }), abs(match.date.timeIntervalSince(entry.date)) < 2 * 3600 else { continue }
            pairs.append((match.height, entry.height))
        }
        guard pairs.count >= 8 else { throw CalibrationError.tooFewPairs(pairs.count) }

        let n = Double(pairs.count)
        let sx = pairs.reduce(0) { $0 + $1.mine }
        let sy = pairs.reduce(0) { $0 + $1.ref }
        let sxx = pairs.reduce(0) { $0 + $1.mine * $1.mine }
        let sxy = pairs.reduce(0) { $0 + $1.mine * $1.ref }
        let denom = n * sxx - sx * sx
        guard abs(denom) > 1e-9 else { throw CalibrationError.parseFailed }
        let a = (n * sxy - sx * sy) / denom
        let b = (sy - a * sx) / n
        let maxResidual = pairs.map { abs(a * $0.mine + b - $0.ref) }.max() ?? 0
        return Fit(scale: (a * 1000).rounded() / 1000,
                   bias: (b * 1000).rounded() / 1000,
                   maxResidual: maxResidual,
                   samples: pairs.count)
    }

    // MARK: Table parsing

    /// The visible day rows. Each row's `?d=YYYYMMDDN` link encodes the
    /// PAGE's base date plus the row index N — the trailing digit is not part
    /// of the date, it must be ADDED as days (decoding it as a date puts the
    /// whole week on day one and garbles the fit; found the hard way).
    /// The row's `title` carries the UTC offset; times and heights cells
    /// match up in order.
    static func parse(_ html: String) throws -> [(date: Date, height: Double)] {
        let rowPattern = try NSRegularExpression(
            pattern: #"id="MareeJours_\d+" title="UTC([+-]\d+)".*?\?d=(\d{8})(\d+)'\);.*?<td>(.*?)</td><td>(.*?)</td>"#,
            options: [.dotMatchesLineSeparators])
        let ns = html as NSString
        var out: [(Date, Double)] = []
        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "yyyyMMdd"

        for m in rowPattern.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            guard let utc = Int(ns.substring(with: m.range(at: 1))),
                  let tz = TimeZone(secondsFromGMT: utc * 3600) else { continue }
            dayFmt.timeZone = tz
            guard let base = dayFmt.date(from: ns.substring(with: m.range(at: 2))),
                  let index = Int(ns.substring(with: m.range(at: 3))) else { continue }
            let day = base.addingTimeInterval(TimeInterval(index) * 86400)
            let times = matches(#"(\d\d)h(\d\d)"#, in: ns.substring(with: m.range(at: 4)))
            let heights = matches(#"([\d,]+)m"#, in: ns.substring(with: m.range(at: 5)))
            guard times.count == heights.count else { continue }
            for (t, h) in zip(times, heights) {
                guard let hour = Int(t[0]), let minute = Int(t[1]),
                      let height = Double(h[0].replacingOccurrences(of: ",", with: "."))
                else { continue }
                out.append((day.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60)), height))
            }
        }
        return out
    }

    private static func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { m in
            (1..<m.numberOfRanges).map { ns.substring(with: m.range(at: $0)) }
        }
    }
}
