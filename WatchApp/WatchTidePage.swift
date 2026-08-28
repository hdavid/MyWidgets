import SwiftUI

/// One tide location as a watch page, drawn exactly like the default tide
/// widget on iOS/macOS: title + coefficients header over the full-bleed
/// 36 h curve (midnight to tomorrow noon, same span as the widget default)
/// with threshold lines, crossing times, extremes and the now-marker.
/// Synthesized locally (TideModel) — the only network ever is the one-time
/// constituent fetch, so a tap just recomputes.
struct WatchTidePage: View {
    /// Chart window past midnight — keep in step with TideSpan's default.
    private static let spanHours = 36

    var location: TideLocation

    @State private var day: DayData?
    @State private var missing = false
    @State private var computing = false

    /// Same fields the widget's TideEntry carries for the chart.
    struct DayData {
        let date: Date
        let start: Date
        let curve: [Double]
        let extremes: [TideExtreme]
        let crossings: [(threshold: Double, date: Date, rising: Bool)]
    }

    var body: some View {
        Group {
            if let day {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(location.title)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        let cal = Calendar.current
                        let coefs = day.extremes
                            .filter { $0.isHigh && cal.isDate($0.date, inSameDayAs: day.date) }
                            .compactMap(\.coefficient)
                        if !coefs.isEmpty {
                            (Text("coef ").foregroundColor(Pal.gray)
                                + Text(coefs.map(String.init).joined(separator: " · "))
                                .foregroundColor(coefs.contains { $0 >= 90 } ? Pal.orange : .primary))
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                    TideChart(start: day.start, step: 600, curve: day.curve,
                              extremes: day.extremes, thresholds: location.thresholds,
                              crossings: day.crossings, days: (Self.spanHours + 23) / 24,
                              date: day.date, nowMarker: true)
                        .frame(maxHeight: .infinity)
                }
            } else {
                NoDataView(message: missing
                           ? "No tide data — needs one fetch with the phone nearby"
                           : "Computing…")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { Task { await compute() } }
        .task(id: location) { await compute() }
        // Recomputing also re-anchors the window on the current midnight, so a
        // page resumed the next morning stops showing yesterday's curve.
        .refreshWhenStale(ttl: Freshness.tide, since: day?.date) { await compute() }
    }

    @MainActor
    private func compute() async {
        // harmonics() may go to the network the first time; don't stack calls.
        guard !computing else { return }
        computing = true
        defer { computing = false }
        let (local, brest) = await TideModel.harmonics(for: location)
        guard let local, let mapping = location.heightMapping else {
            missing = true
            return
        }
        let now = Date()
        let start = Calendar.current.startOfDay(for: now)
        let end = Calendar.current.date(byAdding: .hour, value: Self.spanHours, to: start)
            ?? start.addingTimeInterval(Double(Self.spanHours) * 3600)
        let range = start...end
        day = DayData(
            date: now,
            start: start,
            curve: TideModel.curve(local, mapping: mapping, in: range),
            extremes: TideModel.extremes(local, mapping: mapping,
                                         brest: brest, in: range),
            crossings: location.thresholds.flatMap {
                TideModel.crossings(local, mapping: mapping, of: $0, in: range)
            })
        missing = false
    }
}
