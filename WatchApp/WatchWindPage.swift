import SwiftUI

/// The main screen: one Grafana source, laid out like the small widget —
/// rose + big value, secondary line, chips — sized for a watch. Fetches on
/// appearance, on tap, and whenever what is on screen has aged past
/// Freshness.wind; between fetches the last good snapshot from this process's
/// cache keeps something on screen.
struct WatchWindPage: View {
    var source: GrafanaSource

    @State private var snap: WindSnapshot?
    @State private var stale = false
    @State private var loading = false

    var body: some View {
        Group {
            if let snap {
                let r = WindReading(source: source, snap: snap)
                VStack(spacing: 2) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 3) {
                            TitleRow(r: r, size: 13)
                            HStack(spacing: 8) {
                                if r.hasDirection {
                                    WindRose(deg: r.direction)
                                        .frame(width: 56, height: 56)
                                }
                                VStack(alignment: .leading, spacing: 0) {
                                    PrimaryValue(r: r, size: 30)
                                    SecondaryLine(r: r, size: 13, weight: .medium, stacked: true)
                                }
                            }
                            ForEach(Array(r.chipRows(max: 3).enumerated()), id: \.offset) { _, slots in
                                ChipRow(r: r, slots: slots, size: 13)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    // Below the scroller, not inside it: always visible at the
                    // bottom of the screen, centred.
                    HStack(spacing: 4) {
                        TimestampLine(snap: snap, stale: stale, size: 10)
                        if loading { ProgressView().controlSize(.mini) }
                    }
                }
                .background(alignment: .bottom) {
                    if !snap.series.isEmpty {
                        Sparkline(values: snap.series)
                            .frame(height: 34)
                            .ignoresSafeArea(edges: .bottom)
                    }
                }
            } else {
                NoDataView(message: source.isConfigured
                           ? (loading ? "Loading…" : "No data yet")
                           : "Open My Widgets on the iPhone to sync the config")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { Task { await load() } }
        .task(id: source) { await load() }
        .refreshWhenStale(ttl: Freshness.wind, since: snap?.fetchedAt) { await load() }
    }

    @MainActor
    private func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        // Show the cache instantly; the network answer replaces it.
        if snap == nil, let cached = WindStore.load(for: source.id) {
            snap = cached
            stale = true
        }
        if let fresh = await Grafana.fetchAll(source) {
            WindStore.save(fresh, for: source.id)
            snap = fresh
            stale = false
        } else if snap != nil {
            stale = true
        }
    }
}
