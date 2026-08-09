import SwiftUI
import WidgetKit

// MARK: - Tide accessory views
//
// Shared by the watch complications and the iOS lock-screen families. All of
// them draw one TideModel.Status — pure rendering, no synthesis here.
// Accessory faces render desaturated/monochrome on many watch faces, so
// these use hierarchical white rather than the palette colors.

/// Tide-clock dial: needle turns clockwise through the cycle — straight up
/// at high water, straight down at low — so the needle's vertical component
/// tracks the height. Each threshold becomes a horizontal chord at its
/// normalized height: needle above the line = water above the threshold.
struct TideDial: View {
    let status: TideModel.Status
    let thresholds: [Double]

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2 - 2

            var ring = Path()
            ring.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            ctx.stroke(ring, with: .color(.white.opacity(0.25)), lineWidth: 1.5)

            // HW / LW ticks at 12 and 6 o'clock.
            for sign in [-1.0, 1.0] {
                var tick = Path()
                tick.move(to: CGPoint(x: c.x, y: c.y - sign * (r - 3)))
                tick.addLine(to: CGPoint(x: c.x, y: c.y - sign * r))
                ctx.stroke(tick, with: .color(.white.opacity(0.7)), lineWidth: 2)
            }

            // Threshold chords, dashed. The chord sits where the needle tip
            // passes when the water is exactly at the threshold.
            let span = status.cycleHigh - status.cycleLow
            for t in thresholds where span > 0.1 {
                let v = 2 * (t - status.cycleLow) / span - 1   // -1 (LW) … +1 (HW)
                guard abs(v) < 0.92 else { continue }
                let cy = c.y - CGFloat(v) * r
                let dx = r * CGFloat((1 - v * v).squareRoot())
                var chord = Path()
                chord.move(to: CGPoint(x: c.x - dx, y: cy))
                chord.addLine(to: CGPoint(x: c.x + dx, y: cy))
                ctx.stroke(chord, with: .color(.white.opacity(0.55)),
                           style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            }

        }
    }
}

/// The needle alone, layered above the dial and marked accentable so it
/// takes the watch face's theme color. Phase 0 = HW (up), 0.5 = LW (down),
/// clockwise.
struct TideNeedle: View {
    let phase: Double

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2 - 2
            let a = phase * 2 * .pi
            let tip = CGPoint(x: c.x + r * 0.82 * sin(a), y: c.y - r * 0.82 * cos(a))
            var needle = Path()
            needle.move(to: c)
            needle.addLine(to: tip)
            ctx.stroke(needle, with: .color(.white), lineWidth: 2)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 2, y: c.y - 2, width: 4, height: 4)),
                     with: .color(.white))
        }
    }
}

struct TideCircularView: View {
    let status: TideModel.Status?
    let title: String

    var body: some View {
        // widgetLabel is watchOS-only (the curved text around the dial on
        // Infograph-style faces); the same view runs bare on the iOS lock
        // screen.
        #if os(watchOS)
        dial.widgetLabel { Text(TideText.label(status)) }
        #else
        dial
        #endif
    }

    private var dial: some View {
        // No AccessoryWidgetBackground: the dial draws its own ring, and the
        // standard dim disc just muddied the centre.
        ZStack {
            if let status {
                TideDial(status: status, thresholds: status.thresholds)
                    .padding(1)
                // Needle and number pick up the face's theme color on
                // accented faces; the shadow keeps the number readable where
                // the needle passes behind it.
                TideNeedle(phase: status.phase)
                    .padding(1)
                    .widgetAccentable()
                Text(status.height.formatted(.number.precision(.fractionLength(1))))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .widgetAccentable()
                    .shadow(color: .black.opacity(0.9), radius: 2)
            } else {
                Image(systemName: "water.waves")
            }
        }
    }
}

struct TideRectangularView: View {
    let status: TideModel.Status?
    let title: String

    var body: some View {
        if let status {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let c = status.coefficient {
                        Text("C\(c)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(c >= 90 ? Pal.orange : .primary)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(status.height.formatted(.number.precision(.fractionLength(2))))m")
                        .font(.system(size: 20, weight: .bold))
                    Text(status.rising ? "↗" : "↘")
                        .font(.system(size: 16, weight: .bold))
                    Text("\(status.next.isHigh ? "HW" : "LW") \(TideText.hm(status.next.date))")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                if !status.crossings.isEmpty {
                    Text(status.crossings.prefix(2).map(TideText.crossing).joined(separator: "  "))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("No tide data — open the app once")
                .font(.system(size: 11))
                .foregroundStyle(Pal.gray)
        }
    }
}

/// Text builders shared by the inline family, corner labels and the circular
/// widgetLabel.
enum TideText {
    /// "14h32" — maree.info's time style ("11h08", never "11h8").
    static func hm(_ d: Date) -> String {
        d.formatted(Date.FormatStyle().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
            .replacingOccurrences(of: ":", with: "h")
    }

    /// "3.8↑14h32"
    static func crossing(_ c: (threshold: Double, date: Date, rising: Bool)) -> String {
        "\(c.threshold.formatted(.number.precision(.fractionLength(1))))\(c.rising ? "↑" : "↓")\(hm(c.date))"
    }

    /// "↗ 4.2m · C74 · 3.8↑14h32"
    static func inline(_ status: TideModel.Status?) -> String {
        guard let status else { return "Tide --" }
        var parts = ["\(status.rising ? "↗" : "↘") "
            + "\(status.height.formatted(.number.precision(.fractionLength(1))))m"]
        if let c = status.coefficient { parts.append("C\(c)") }
        if let first = status.crossings.first { parts.append(crossing(first)) }
        return parts.joined(separator: " · ")
    }

    /// "C74 · 3.8↑14h32" — coefficient plus the nearest crossing.
    static func label(_ status: TideModel.Status?) -> String {
        guard let status else { return "" }
        var parts: [String] = []
        if let c = status.coefficient { parts.append("C\(c)") }
        if let first = status.crossings.min(by: { $0.date < $1.date }) {
            parts.append(crossing(first))
        }
        return parts.joined(separator: " · ")
    }
}
