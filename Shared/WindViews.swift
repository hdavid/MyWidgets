import SwiftUI
import WidgetKit

// MARK: - Wind rose (vector — adapts to light/dark instantly)

struct WindRose: View {
    var deg: Double
    var showLetters = true

    var body: some View {
        Canvas { ctx, size in
            let side = min(size.width, size.height)
            let s = side / 80
            let c = CGPoint(x: side / 2, y: side / 2)
            let art = Pal.art

            // Outer circle
            ctx.stroke(
                Path(ellipseIn: CGRect(x: 5*s, y: 5*s, width: side - 10*s, height: side - 10*s)),
                with: .color(art.opacity(0.8)),
                lineWidth: 2*s
            )

            // Dots for 8 directions
            for i in 0..<8 {
                let angle = Double(i) * 45 * .pi / 180
                let r = (side - 16*s) / 2
                let x = c.x + r * sin(angle)
                let y = c.y - r * cos(angle)
                ctx.fill(
                    Path(ellipseIn: CGRect(x: x - 2*s, y: y - 2*s, width: 4*s, height: 4*s)),
                    with: .color(art.opacity(0.8))
                )
            }

            // Cardinal letters
            if showLetters {
                let cardinals: [(String, Double)] = [("N", 0), ("E", 90), ("S", 180), ("W", 270)]
                for (letter, a) in cardinals {
                    let angle = a * .pi / 180
                    let r = (side - 2*s) / 2 - 12*s
                    let x = c.x + r * sin(angle)
                    let y = c.y - r * cos(angle)
                    ctx.draw(
                        Text(letter).font(.system(size: 11*s, weight: .bold)).foregroundStyle(art),
                        at: CGPoint(x: x, y: y)
                    )
                }
            }

            // Direction arrow points INTO the wind — where it comes from
            // (weather-vane convention; dir_deg is the FROM direction)
            let rad = deg * .pi / 180
            let outerR = (side - 10*s) / 2
            let tail = CGPoint(x: c.x - (outerR - 25*s) * sin(rad),
                               y: c.y + (outerR - 25*s) * cos(rad))
            let tip = CGPoint(x: c.x + (outerR - 5*s) * sin(rad),
                              y: c.y - (outerR - 5*s) * cos(rad))
            let headLen = 50 * s
            let leftRad = rad + .pi / 8
            let rightRad = rad - .pi / 8

            var tri = Path()
            tri.move(to: tip)
            tri.addLine(to: CGPoint(x: tip.x - headLen * sin(leftRad),
                                    y: tip.y + headLen * cos(leftRad)))
            tri.addLine(to: tail)
            tri.addLine(to: CGPoint(x: tip.x - headLen * sin(rightRad),
                                    y: tip.y + headLen * cos(rightRad)))
            tri.closeSubpath()
            ctx.fill(tri, with: .color(art))
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - 1h wind sparkline (background)

struct Sparkline: View {
    var values: [Double?]

    var body: some View {
        Canvas { ctx, size in
            let valid = values.compactMap { $0 }
            guard values.count >= 2, let maxV = valid.max(), maxV > 0 else { return }
            let n = values.count
            let stepX = size.width / CGFloat(n - 1)

            func point(_ i: Int, _ v: Double) -> CGPoint {
                CGPoint(x: CGFloat(i) * stepX,
                        y: size.height - CGFloat(v / maxV) * size.height)
            }

            // Line (gaps where data is missing)
            var line = Path()
            var started = false
            for (i, v) in values.enumerated() {
                guard let v else { started = false; continue }
                let p = point(i, v)
                if started { line.addLine(to: p) } else { line.move(to: p); started = true }
            }
            ctx.stroke(line, with: .color(Pal.chart.opacity(0.55)), lineWidth: 2.5)

            // Fill under the curve
            var fill = Path()
            var first: CGPoint?
            var last: CGPoint?
            for (i, v) in values.enumerated() {
                guard let v else { continue }
                let p = point(i, v)
                if first == nil { fill.move(to: p); first = p } else { fill.addLine(to: p) }
                last = p
            }
            if let first, let last {
                fill.addLine(to: CGPoint(x: last.x, y: size.height))
                fill.addLine(to: CGPoint(x: first.x, y: size.height))
                fill.closeSubpath()
                ctx.fill(fill, with: .color(Pal.chart.opacity(0.16)))
            }
        }
    }
}

// MARK: - Reading a snapshot through the configured slots
//
// Everything below draws from this instead of named snapshot fields: the slot
// list decides which metrics exist, what they're called and how they're tinted.

struct WindReading {
    let source: GrafanaSource
    let snap: WindSnapshot

    /// Feeds the `.dewSpread` scale, which needs the current temperature to
    /// judge how close a dew point is.
    private var temperatureRef: Double? {
        snap.value(source.slots.first { $0.scale == .temperature && $0.enabled })
    }

    func value(_ role: SlotRole) -> Double? { snap.value(source.slot(role)) }

    func text(_ role: SlotRole) -> String? {
        guard let slot = source.slot(role) else { return nil }
        return slot.text(snap.value(slot), trend: snap.trend(slot))
    }

    func color(_ role: SlotRole) -> Color {
        guard let slot = source.slot(role) else { return Pal.gray }
        return slot.scale.color(snap.value(slot), reference: temperatureRef)
    }

    func text(_ slot: MetricSlot) -> String {
        slot.text(snap.value(slot), trend: snap.trend(slot))
    }

    func color(_ slot: MetricSlot) -> Color {
        slot.scale.color(snap.value(slot), reference: temperatureRef)
    }

    var hasDirection: Bool { source.slot(.direction) != nil }
    var direction: Double { value(.direction) ?? 0 }

    /// "SSW 210°" for the header, nil when no direction slot is configured.
    var compass: String? {
        guard let slot = source.slot(.direction), let d = snap.value(slot) else { return nil }
        return "\(degToCompass(d)) \(fmtN(d, slot.decimals))\(slot.unit)"
    }

    /// "Gust 12.4 · max 15.1" — the line under the big number.
    var secondaryLine: [(role: SlotRole, text: String)] {
        [SlotRole.secondary, .tertiary].compactMap { role in
            text(role).map { (role, $0) }
        }
    }

    func chipRows(max rows: Int) -> [[MetricSlot]] {
        Array(source.chipRows.prefix(rows))
    }
}

// MARK: - Shared rows

struct TitleRow: View {
    var r: WindReading
    var size: CGFloat

    var body: some View {
        HStack {
            Text(r.source.title)
                .font(.system(size: size, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 2)
            if let compass = r.compass {
                Text(compass)
                    .font(.system(size: size, weight: .bold))
                    .foregroundStyle(Pal.gray)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }
}

/// One row of chips (up to three), each tinted by its own scale.
struct ChipRow: View {
    var r: WindReading
    var slots: [MetricSlot]
    var size: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            ForEach(slots) { slot in
                Text(r.text(slot))
                    .foregroundStyle(r.color(slot))
            }
        }
        .font(.system(size: size, weight: .semibold))
        .lineLimit(1)
        .fixedSize()
    }
}

/// The "Gust 12.4 · max 15.1" line, joined from whichever slots are set.
struct SecondaryLine: View {
    var r: WindReading
    var size: CGFloat
    var weight: Font.Weight = .semibold
    /// One item per line. Only where the family has the height for it — small
    /// stays on a single joined line.
    var stacked = false

    /// One concatenated Text rather than an HStack of Texts.
    ///
    /// This line shares the middle column with the big value, and on the medium
    /// layout the chip rows next to it are `.fixedSize()` — they claim their
    /// intrinsic width, so the column gets squeezed. A squeezed HStack truncates
    /// its children individually ("Gust 5.6 · max 7.8" → "Gust… · max…"), while a
    /// single Text scales as a unit under minimumScaleFactor. Per-part colour
    /// survives concatenation, which is why this doesn't cost anything.
    private var line: Text? {
        r.secondaryLine.reduce(nil) { acc, item in
            let piece = Text(item.text).foregroundColor(r.color(item.role))
            guard let acc else { return piece }
            return acc + Text(" · ").foregroundColor(Pal.gray) + piece
        }
    }

    var body: some View {
        if stacked {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(r.secondaryLine, id: \.role) { item in
                    Text(item.text)
                        .foregroundStyle(r.color(item.role))
                        .font(.system(size: size, weight: weight))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }
        } else if let line {
            line
                .font(.system(size: size, weight: weight))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }
}

/// The big headline value.
struct PrimaryValue: View {
    var r: WindReading
    var size: CGFloat

    var body: some View {
        Text(r.text(.primary) ?? "--")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(r.color(.primary))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

struct TimestampLine: View {
    var snap: WindSnapshot
    var stale: Bool
    var size: CGFloat

    var body: some View {
        if stale {
            Text("Offline · last \(timeText(snap.measuredAt))")
                .font(.system(size: size))
                .foregroundStyle(Pal.red)
                .lineLimit(1)
                .fixedSize()
        } else {
            Text("Measured at \(timeText(snap.measuredAt))")
                .font(.system(size: size))
                .foregroundStyle(ageColor(snap.measuredAt))
                .lineLimit(1)
                .fixedSize()
        }
    }
}

// MARK: - Family layouts

struct SmallWindView: View {
    var r: WindReading
    var stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            TitleRow(r: r, size: 11)
            HStack(spacing: 8) {
                if r.hasDirection {
                    WindRose(deg: r.direction)
                        .frame(width: 54, height: 54)
                }
                PrimaryValue(r: r, size: 30)
            }
            SecondaryLine(r: r, size: 13, weight: .medium)
            ForEach(Array(r.chipRows(max: 2).enumerated()), id: \.offset) { _, slots in
                ChipRow(r: r, slots: slots, size: 13)
            }
            Spacer(minLength: 0)
            TimestampLine(snap: r.snap, stale: stale, size: 9)
        }
    }
}

struct MediumWindView: View {
    var r: WindReading
    var stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TitleRow(r: r, size: 13)
            HStack(spacing: 8) {
                if r.hasDirection {
                    WindRose(deg: r.direction)
                        .frame(width: 64, height: 64)
                }
                VStack(alignment: .leading, spacing: 0) {
                    PrimaryValue(r: r, size: 32)
                    SecondaryLine(r: r, size: 13, stacked: true)
                }
                .layoutPriority(1)
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 5) {
                    ForEach(Array(r.chipRows(max: 2).enumerated()), id: \.offset) { _, slots in
                        ChipRow(r: r, slots: slots, size: 15)
                    }
                }
            }
            Spacer(minLength: 0)
            TimestampLine(snap: r.snap, stale: stale, size: 9)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

struct LargeWindView: View {
    var r: WindReading
    var stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TitleRow(r: r, size: 17)
            Spacer()
            HStack(spacing: 18) {
                if r.hasDirection {
                    WindRose(deg: r.direction)
                        .frame(width: 130, height: 130)
                }
                VStack(alignment: .leading, spacing: 2) {
                    PrimaryValue(r: r, size: 48)
                    SecondaryLine(r: r, size: 20, weight: .regular, stacked: true)
                }
                Spacer(minLength: 0)
            }
            Spacer()
            ForEach(Array(r.chipRows(max: 3).enumerated()), id: \.offset) { i, slots in
                HStack {
                    ChipRow(r: r, slots: slots, size: 18)
                    Spacer()
                }
                .padding(.bottom, i == 0 ? 6 : 0)
            }
            Spacer()
            TimestampLine(snap: r.snap, stale: stale, size: 12)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

// MARK: - No-data fallback

struct NoDataView: View {
    var message = "No data yet"

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "wind")
                .font(.title)
                .foregroundStyle(Pal.gray)
            Text(message)
                .font(.caption)
                .foregroundStyle(Pal.gray)
                .multilineTextAlignment(.center)
        }
        .padding(8)
    }
}
