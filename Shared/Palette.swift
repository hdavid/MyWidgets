import Foundation
import SwiftUI

// MARK: - Theme-adaptive palette (true dynamic colors: adapt instantly)
//
// Lives in Shared rather than the widget target because the app's settings
// tabs need the same colors to preview a metric's scale.

private func dyn(_ light: String, _ dark: String) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return NSColor(hex: isDark ? dark : light)
    })
}

extension NSColor {
    convenience init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: String(hex.dropFirst())).scanHexInt64(&v)
        self.init(red: CGFloat((v >> 16) & 0xff) / 255,
                  green: CGFloat((v >> 8) & 0xff) / 255,
                  blue: CGFloat(v & 0xff) / 255,
                  alpha: 1)
    }
}

enum Pal {
    static let gray      = dyn("#48484d", "#98989d")
    static let blue      = dyn("#0857b8", "#64a0ff")
    static let lightblue = dyn("#2f5e85", "#87ceeb")
    static let green     = dyn("#0f6628", "#30d158")
    static let yellow    = dyn("#755a00", "#ffd60a")
    static let orange    = dyn("#8f4300", "#ff9f0a")
    static let red       = dyn("#b8000f", "#ff453a")
    static let purple    = dyn("#54419e", "#8b84f2")
    static let deepblue  = dyn("#000080", "#5050ff")
    static let art       = dyn("#5f5f66", "#aaaab2")   // rose
    static let chart     = dyn("#0a7aff", "#64a0ff")   // background wind graph
    static let bg        = dyn("#f2f2f7", "#1c1c1e")
}

// MARK: - Color scales (same thresholds as the iOS widget)

func windColor(_ v: Double?) -> Color {
    guard let v else { return Pal.gray }
    if v < 4 { return Pal.gray }
    if v < 7 { return Pal.blue }
    if v < 11 { return Pal.green }
    if v < 22 { return Pal.yellow }
    return Pal.red
}

func temperatureColor(_ v: Double?) -> Color {
    guard let v else { return Pal.gray }
    if v < 0 { return Pal.blue }
    if v < 10 { return Pal.lightblue }
    if v < 20 { return Pal.green }
    if v < 25 { return Pal.yellow }
    if v < 30 { return Pal.orange }
    return Pal.red
}

func humidityColor(_ v: Double?) -> Color {
    guard let v else { return Pal.gray }
    if v < 40 { return Pal.red }
    if v < 60 { return Pal.yellow }
    if v < 80 { return Pal.green }
    return Pal.blue
}

func pressureColor(_ v: Double?) -> Color {
    guard let v else { return Pal.gray }
    if v < 980 { return Pal.red }
    if v < 995 { return Pal.orange }
    if v < 1010 { return Pal.yellow }
    if v < 1025 { return Pal.green }
    if v < 1035 { return Pal.blue }
    return Pal.deepblue
}

func dewSpreadColor(temp: Double?, dew: Double?) -> Color {
    guard let temp, let dew else { return Pal.gray }
    let spread = temp - dew
    if spread < 2.5 { return Pal.red }
    if spread < 4 { return Pal.orange }
    if spread < 6 { return Pal.yellow }
    if spread < 10 { return Pal.green }
    if spread < 15 { return Pal.lightblue }
    return Pal.blue
}

func solarColor(_ v: Double?) -> Color {
    guard let v else { return Pal.gray }
    if v < 1 { return Pal.gray }
    if v < 50 { return Pal.purple }
    if v < 200 { return Pal.blue }
    if v < 400 { return Pal.green }
    if v < 600 { return Pal.yellow }
    if v < 800 { return Pal.orange }
    return Pal.red
}

func ageColor(_ measuredAt: Date?) -> Color {
    guard let measuredAt else { return Pal.gray }
    let ageMin = Date().timeIntervalSince(measuredAt) / 60
    if ageMin > 30 { return Pal.red }
    if ageMin > 10 { return Pal.orange }
    return Pal.gray
}

// MARK: - Named scale (what a configurable metric slot picks from)

/// The color ramp a metric is drawn with. Thresholds stay in code — the point
/// of the picker is choosing a ramp that suits the quantity, not retuning it.
enum MetricScale: String, Codable, CaseIterable, Identifiable {
    case none, wind, temperature, humidity, pressure, dewSpread, solar

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none:        return "Plain"
        case .wind:        return "Wind (kn)"
        case .temperature: return "Temperature (°C)"
        case .humidity:    return "Humidity (%)"
        case .pressure:    return "Pressure (hPa)"
        case .dewSpread:   return "Dew spread"
        case .solar:       return "Solar (W/m²)"
        }
    }

    /// `reference` is only used by `.dewSpread`, which colors by how close the
    /// value sits to the temperature slot's value rather than by its own level.
    func color(_ v: Double?, reference: Double? = nil) -> Color {
        switch self {
        case .none:        return v == nil ? Pal.gray : .primary
        case .wind:        return windColor(v)
        case .temperature: return temperatureColor(v)
        case .humidity:    return humidityColor(v)
        case .pressure:    return pressureColor(v)
        case .dewSpread:   return dewSpreadColor(temp: reference, dew: v)
        case .solar:       return solarColor(v)
        }
    }
}

// MARK: - Helpers

func degToCompass(_ deg: Double) -> String {
    let dirs = ["N","NNE","NE","ENE","E","ESE","SE","SSE",
                "S","SSW","SW","WSW","W","WNW","NW","NNW"]
    return dirs[Int((deg / 22.5).rounded()) % 16]
}

/// 3h pressure tendency arrow (standard meteo thresholds ~1.6 hPa / 3h)
func pressureTrend(_ now: Double?, _ ago: Double?) -> String {
    guard let now, let ago else { return "" }
    let d = now - ago
    if d >= 2 { return "↑" }
    if d >= 0.5 { return "↗" }
    if d <= -2 { return "↓" }
    if d <= -0.5 { return "↘" }
    return "→"
}

// MARK: - Formatting

func fmt1(_ v: Double?) -> String {
    guard let v else { return "--" }
    return String(format: "%.1f", v)
}

func fmt0(_ v: Double?) -> String {
    guard let v else { return "--" }
    return String(Int(v.rounded()))
}

/// Value formatted to a slot's decimal count.
func fmtN(_ v: Double?, _ decimals: Int) -> String {
    guard let v else { return "--" }
    return String(format: "%.\(max(0, min(3, decimals)))f", v)
}

func timeText(_ d: Date?) -> String {
    guard let d else { return "--:--" }
    let f = DateFormatter()
    if Calendar.current.isDateInToday(d) {
        f.dateFormat = "HH:mm"
    } else {
        f.dateFormat = "yyyy-MM-dd HH:mm"
    }
    return f.string(from: d)
}
