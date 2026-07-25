import SwiftUI

/// Short "time until reset" like "2h5m", "3d", "45m", or "now".
func resetText(_ date: Date?, now: Date = Date()) -> String? {
    guard let date else { return nil }
    let s = date.timeIntervalSince(now)
    if s <= 0 { return "now" }
    let totalMin = Int(s / 60)
    let d = totalMin / 1440
    let h = (totalMin % 1440) / 60
    let m = totalMin % 60
    if d > 0 { return h > 0 ? "\(d)d\(h)h" : "\(d)d" }
    if h > 0 { return "\(h)h\(m)m" }
    return "\(m)m"
}

/// Shared column geometry so the header labels line up with the ring columns.
enum RowMetrics {
    static func ring(_ compact: Bool) -> CGFloat { compact ? 40 : 48 }
    static func clusterSpacing(_ compact: Bool) -> CGFloat { compact ? 6 : 8 }
    static func rowSpacing(_ compact: Bool) -> CGFloat { compact ? 10 : 12 }
    static func infoWidth(_ compact: Bool) -> CGFloat { compact ? 104 : 132 }
}

/// A colored donut gauge: optional title above, % in the center, reset below.
struct RingGauge: View {
    let title: String
    let gauge: QuotaGauge
    var size: CGFloat = 40
    var showReset: Bool = true
    var showTitle: Bool = true

    private var lineWidth: CGFloat { max(3, size * 0.16) }

    var body: some View {
        VStack(spacing: size * 0.09) {
            if showTitle {
                Text(title)
                    .font(.system(size: size * 0.3, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.6).fixedSize()
            }
            ZStack {
                Circle().stroke(Color.primary.opacity(0.12), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: max(0.001, gauge.fraction))
                    .stroke(gauge.color,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(gauge.percent.map { "\($0)" } ?? "–")
                    .font(.system(size: size * 0.4, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(gauge.percent == nil ? Color.secondary : gauge.color)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .frame(width: size, height: size)
            if showReset {
                Text(resetText(gauge.resetDate).map { "↻\($0)" } ?? "—")
                    .font(.system(size: size * 0.28, weight: .semibold, design: .rounded))
                    .foregroundStyle(gauge.percent == nil ? Color.secondary.opacity(0.5)
                                                          : .primary.opacity(0.6))
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
        }
    }
}

/// The column labels (5h / Week / Fable), shown ONCE above the rows so they
/// aren't repeated on every account. Aligns with the ring columns below.
struct ColumnHeader: View {
    var compact: Bool = false
    var tight: Bool = false   // widget: rings clustered; app: spread across width

    var body: some View {
        if tight {
            HStack(spacing: RowMetrics.clusterSpacing(compact)) {
                label("5h").frame(width: RowMetrics.ring(compact))
                label("Week").frame(width: RowMetrics.ring(compact))
                label("Fable").frame(width: RowMetrics.ring(compact))
                Spacer(minLength: 0)
            }
        } else {
            HStack(spacing: RowMetrics.rowSpacing(compact)) {
                label("5h").frame(maxWidth: .infinity)
                label("Week").frame(maxWidth: .infinity)
                label("Fable").frame(maxWidth: .infinity)
                Color.clear.frame(width: RowMetrics.infoWidth(compact), height: 1)
            }
        }
    }
    private func label(_ t: String) -> some View {
        Text(t)
            .font(.system(size: compact ? 11 : 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
    }
}

/// One account: three donut gauges spread across the width (labels come from
/// ColumnHeader), then the friendly name + CLI, and the 5h reset time.
struct AccountRow: View {
    let account: Account
    var isBest: Bool = false
    var compact: Bool = false
    var tight: Bool = false   // widget: rings clustered; app: spread across width

    private var ringSize: CGFloat { RowMetrics.ring(compact) }

    var body: some View {
        HStack(alignment: .center, spacing: RowMetrics.rowSpacing(compact)) {
            if tight {
                HStack(spacing: RowMetrics.clusterSpacing(compact)) {
                    rings
                }
                infoColumn.frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Group { rings }.frame(maxWidth: .infinity)
                infoColumn.frame(width: RowMetrics.infoWidth(compact), alignment: .leading)
            }
        }
        .opacity(account.needsAttention ? 0.7 : 1)
    }

    @ViewBuilder private var rings: some View {
        RingGauge(title: "5h", gauge: account.fiveHour, size: ringSize,
                  showReset: false, showTitle: false)
        RingGauge(title: "Week", gauge: account.week, size: ringSize,
                  showReset: false, showTitle: false)
        RingGauge(title: "Fable", gauge: account.fable, size: ringSize,
                  showReset: false, showTitle: false)
    }

    private var infoColumn: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 4) {
            nameLine.lineLimit(1).minimumScaleFactor(0.6)
            if let status = account.statusText {
                Label(status, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: compact ? 9 : 11, weight: .semibold))
                    .foregroundStyle(.orange).lineLimit(1).minimumScaleFactor(0.7)
            } else if tight {
                // Widget: both resets on one line — there's room on the right.
                HStack(spacing: 10) {
                    ResetLine(label: "5h", gauge: account.fiveHour, compact: compact)
                    ResetLine(label: "", gauge: account.week, compact: compact)
                }
            } else {
                ResetLine(label: "5h", gauge: account.fiveHour, compact: compact)
                ResetLine(label: "", gauge: account.week, compact: compact)
            }
        }
    }

    // Friendly name (+ ✓ when best).
    private var nameLine: Text {
        var t = Text(account.displayName)
            .font(.system(size: compact ? 16 : 16, weight: .bold))
        if isBest {
            t = t + Text("  ")
                + Text(Image(systemName: "checkmark.seal.fill")).foregroundColor(.green)
        }
        return t
    }
}

/// One reset line: "5h ↻54m" / "Wk ↻6d6h".
struct ResetLine: View {
    let label: String
    let gauge: QuotaGauge
    var compact: Bool = false

    var body: some View {
        let sz: CGFloat = compact ? 13 : 13.5
        HStack(spacing: 4) {
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: sz, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Text(resetText(gauge.resetDate).map { "↻\($0)" } ?? "—")
                .font(.system(size: sz, weight: .bold, design: .rounded))
                .foregroundStyle(gauge.percent == nil ? Color.secondary : .primary)
                .lineLimit(1)
        }
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "hourglass").font(.title2).foregroundStyle(.secondary)
            Text("No data yet").font(.system(size: 11, weight: .semibold))
            Text("Open My Widgets from the menu bar to refresh")
                .font(.system(size: 9)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Ranking ("which account to use")

enum Ranking {
    /// Best = logged-in, no error, lowest worst-quota. Ties broken by array order.
    static func best(_ accounts: [Account]) -> Account? {
        accounts
            .filter { $0.loggedIn && $0.error == nil }
            .min { $0.worstPercent < $1.worstPercent }
    }
    static func bestAccountID(_ accounts: [Account]) -> String? { best(accounts)?.id }
}
