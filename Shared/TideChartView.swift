import SwiftUI

// MARK: - Tide curve chart
//
// The one-day / multi-day tide chart the iOS/macOS widgets draw, shared with
// the watch app's tide page so every platform shows the same picture. The
// curve, threshold lines with crossing times, extremes labels, day rules and
// now-marker are all one Canvas — widget-host layout stays one node deep
// (see the note on ForecastLine about per-view cost).
struct TideChart: View {
    /// Curve start and sampling step for mapping index → time.
    let start: Date
    let step: TimeInterval
    let curve: [Double]
    let extremes: [TideExtreme]
    let thresholds: [Double]
    /// Threshold crossings inside the curve range, for the on-line labels.
    let crossings: [(threshold: Double, date: Date, rising: Bool)]
    /// Days covered by the curve (1 = today widget layout).
    let days: Int
    /// "Now" for the marker.
    let date: Date
    /// Show the now-marker (today layouts only).
    let nowMarker: Bool
    /// Space reserved for the overlaid header when drawn full-bleed.
    var topInset: CGFloat = 0

    var body: some View {
        Canvas { ctx, size in
            guard curve.count > 1 else { return }
            let labelTop: CGFloat = topInset + 14   // room for HW time labels
            let labelBottom: CGFloat = 12           // room for LW time labels
            let dayBand: CGFloat = days > 1 ? 13 : 0
            let lo = min(curve.min() ?? 0, thresholds.min() ?? .infinity) - 0.3
            let hi = max(curve.max() ?? 1, thresholds.max() ?? -.infinity) + 0.3
            let plotH = size.height - labelTop - labelBottom - dayBand
            let total = Double(curve.count - 1) * step

            func x(_ d: Date) -> CGFloat {
                CGFloat(d.timeIntervalSince(start) / total) * size.width
            }
            func y(_ h: Double) -> CGFloat {
                dayBand + labelTop + plotH * CGFloat(1 - (h - lo) / (hi - lo))
            }

            // Day separators + per-day labels and coefficients. A week of
            // slices leaves ~1/7 of the width per day, so labels shrink to
            // the narrow weekday there.
            let week = days > 4
            if days > 1 {
                let cal = Calendar.current
                let fmt = week ? Date.FormatStyle().weekday(.narrow).day()
                               : Date.FormatStyle().weekday(.abbreviated).day()
                for d in 0..<days {
                    guard let dayStart = cal.date(byAdding: .day, value: d, to: start)
                    else { continue }
                    let xd = x(dayStart)
                    if d > 0 {
                        var rule = Path()
                        rule.move(to: CGPoint(x: xd, y: topInset))
                        rule.addLine(to: CGPoint(x: xd, y: size.height))
                        ctx.stroke(rule, with: .color(Pal.gray.opacity(0.25)), lineWidth: 1)
                    }
                    let coefs = extremes
                        .filter { $0.isHigh && cal.isDate($0.date, inSameDayAs: dayStart) }
                        .compactMap(\.coefficient)
                    let label = Text(dayStart.formatted(fmt))
                        .font(.system(size: 9, weight: .semibold)).foregroundColor(Pal.gray)
                    ctx.draw(ctx.resolve(label), at: CGPoint(x: xd + 3, y: topInset + 6),
                             anchor: .leading)
                    if !coefs.isEmpty {
                        // A week's ~1/7 slice can't fit "96·97" next to the
                        // day label without colliding — the day's max alone
                        // tells the spring/neap story there.
                        let text = week ? String(coefs.max() ?? 0)
                                        : coefs.map(String.init).joined(separator: "·")
                        let c = Text(text)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(coefs.contains { $0 >= 90 } ? Pal.orange : .primary)
                        // The last day can be partial (36 h span), so anchor to
                        // where the day actually ends, not an equal-width slice.
                        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)
                            .map { min(x($0), size.width) } ?? size.width
                        ctx.draw(ctx.resolve(c), at: CGPoint(x: dayEnd - 3, y: topInset + 6),
                                 anchor: .trailing)
                    }
                }
            }

            // Curve + fill.
            var line = Path()
            for (i, h) in curve.enumerated() {
                let p = CGPoint(x: size.width * CGFloat(i) / CGFloat(curve.count - 1), y: y(h))
                i == 0 ? line.move(to: p) : line.addLine(to: p)
            }
            var fill = line
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()
            ctx.fill(fill, with: .color(Pal.chart.opacity(0.14)))
            ctx.stroke(line, with: .color(Pal.chart), lineWidth: 1.8)

            // Labels already placed, so later ones can dodge them.
            var placed: [CGRect] = []
            func claim(_ center: CGPoint, _ text: String, size fontSize: CGFloat) -> CGRect {
                let w = CGFloat(text.count) * fontSize * 0.62 + 4
                let r = CGRect(x: center.x - w / 2, y: center.y - 6, width: w, height: 12)
                placed.append(r)
                return r
            }

            // Threshold lines, dashed, height tag at the right edge; on the
            // today chart every crossing is labelled on the line itself,
            // rising above with "↑", falling below with "↓".
            for threshold in thresholds {
                let ty = y(threshold)
                var thr = Path()
                thr.move(to: CGPoint(x: 0, y: ty))
                thr.addLine(to: CGPoint(x: size.width, y: ty))
                ctx.stroke(thr, with: .color(Pal.green.opacity(0.8)),
                           style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                let tag = Text(threshold.formatted(.number.precision(.fractionLength(1))))
                    .font(.system(size: 8, weight: .medium)).foregroundColor(Pal.green)
                ctx.draw(ctx.resolve(tag), at: CGPoint(x: size.width - 2, y: ty - 6), anchor: .trailing)

                // Crossing labels belong to the now-marker layouts (today
                // widget, watch page) whatever their span; the days widget
                // is too dense for them.
                if nowMarker {
                    for c in crossings where c.threshold == threshold {
                        let cx = x(c.date)
                        guard cx > 14, cx < size.width - 20 else { continue }
                        let text = "\(c.rising ? "↑" : "↓")\(TideText.hm(c.date))"
                        let at = CGPoint(x: cx, y: ty + (c.rising ? 7 : -7))
                        _ = claim(at, text, size: 8)
                        let label = Text(text)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(Pal.green)
                        ctx.draw(ctx.resolve(label), at: at, anchor: .center)
                    }
                }
            }

            // Extremes: time above the highs (with height when there's room),
            // time below the lows. Dense charts drop the height; a full week
            // drops the minutes too ("14h"), or neighbours overlap.
            let dense = days > 2
            for e in extremes {
                let px = x(e.date)
                guard px >= 0, px <= size.width else { continue }
                let time = TideText.hm(e.date)
                let label = week ? "\(Calendar.current.component(.hour, from: e.date))h"
                    : dense ? time
                    : "\(time) \(e.height.formatted(.number.precision(.fractionLength(1))))m"
                let text = Text(label)
                    .font(.system(size: 8.5, weight: e.isHigh ? .semibold : .regular))
                    .foregroundColor(e.isHigh ? .primary : Pal.gray)
                let py = e.isHigh ? y(e.height) - 8 : y(e.height) + 8
                let ax = min(max(px, 22), size.width - 22)
                if week {
                    // Edge clamping piles neighbours onto the same spot on a
                    // week chart — skip a label rather than overlap the last.
                    let w = CGFloat(label.count) * 8.5 * 0.62 + 4
                    let r = CGRect(x: ax - w / 2, y: py - 6, width: w, height: 12)
                    if placed.contains(where: { $0.intersects(r) }) { continue }
                    placed.append(r)
                } else {
                    _ = claim(CGPoint(x: ax, y: py), label, size: 8.5)
                }
                ctx.draw(ctx.resolve(text), at: CGPoint(x: ax, y: py), anchor: .center)
            }

            // Now: marker line, dot on the curve, and the current height
            // beside the dot (side away from the nearest edge).
            if nowMarker {
                let nx = x(date)
                if nx >= 0, nx <= size.width {
                    var mark = Path()
                    mark.move(to: CGPoint(x: nx, y: dayBand + labelTop))
                    mark.addLine(to: CGPoint(x: nx, y: size.height - labelBottom))
                    ctx.stroke(mark, with: .color(Pal.red.opacity(0.55)), lineWidth: 1)
                    let idx = Int(date.timeIntervalSince(start) / step)
                    if curve.indices.contains(idx) {
                        let ny = y(curve[idx])
                        let dot = CGRect(x: nx - 2.5, y: ny - 2.5, width: 5, height: 5)
                        ctx.fill(Path(ellipseIn: dot), with: .color(Pal.red))
                        let text = curve[idx].formatted(.number.precision(.fractionLength(2))) + "m"
                        let label = Text(text)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Pal.red)
                        // Try beside the dot first, then above/below, on the
                        // side away from the edge — first spot free of other
                        // labels wins.
                        let left = nx > size.width * 0.8
                        let dx: CGFloat = left ? -20 : 20
                        let candidates = [
                            CGPoint(x: nx + dx, y: ny - 8),
                            CGPoint(x: nx + dx, y: ny + 9),
                            CGPoint(x: nx + dx, y: ny - 20),
                            CGPoint(x: nx + dx, y: ny + 21),
                        ]
                        let w = CGFloat(text.count) * 9 * 0.62 + 4
                        let spot = candidates.first { c in
                            let r = CGRect(x: c.x - w / 2, y: c.y - 6, width: w, height: 12)
                            return !placed.contains { $0.intersects(r) }
                        } ?? candidates[0]
                        ctx.draw(ctx.resolve(label), at: spot, anchor: .center)
                    }
                }
            }
        }
    }
}
