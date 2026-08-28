import Combine
import SwiftUI

/// How long fetched data stays good enough to show as-is — one home for every
/// "how old is too old" number. The widget timeline policies and the watch
/// pages' auto-refresh both read these, so a complication and the app never
/// disagree about what counts as fresh.
enum Freshness {
    /// Live station readings: the sources behind them publish every few minutes.
    static let wind: TimeInterval = 5 * 60

    /// Windguru model runs land a few times a day, so an hour is plenty; the
    /// hourly pass mostly re-anchors the strip to the current time.
    static let forecast: TimeInterval = 60 * 60

    /// Synthesized locally, so the only cost is a little CPU. Short enough that
    /// the now-marker keeps up and a page left open overnight redraws around
    /// today's midnight instead of yesterday's.
    static let tide: TimeInterval = 10 * 60

    /// Webcams carry their own interval (`CamSpec.refreshMinutes`); this is what
    /// a cam that hasn't been resolved yet falls back to.
    static let camFallback: TimeInterval = 5 * 60
}

// MARK: - Auto-refresh when past the TTL

/// Re-fetches what a page is showing once it has aged past `ttl`: immediately
/// on returning to the foreground, and on a timer while the page is on screen.
///
/// Why a page's `.task` isn't enough: watchOS keeps a suspended app's view
/// hierarchy alive, so raising the wrist an hour — or a day — later resumes the
/// very same views. `.task` does not run a second time, and the screen goes on
/// showing whenever the last fetch happened to be.
private struct RefreshWhenStale: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    let ttl: TimeInterval
    /// When the data on display was fetched; nil means there is none yet.
    let dataDate: Date?
    let refresh: () async -> Void

    /// How often the check runs while on screen. The TTL still decides whether
    /// a check fetches anything, so this only sets how soon after expiry the
    /// refresh lands. Held in @State because the modifier is rebuilt on every
    /// render, and a fresh publisher each time would restart the timer forever.
    @State private var ticker = Timer.publish(every: 60, on: .main, in: .common)
        .autoconnect()

    func body(content: Content) -> some View {
        content
            // Coming back to the foreground is the moment that matters most:
            // it is the one where a whole night may have passed.
            .onChange(of: scenePhase) { was, now in
                guard now == .active, was != .active else { return }
                Task { await refreshIfStale() }
            }
            // A timer, not a sleeping task: onReceive runs the closure from the
            // current body, so it always sees the current `dataDate`.
            .onReceive(ticker) { _ in
                guard scenePhase == .active else { return }
                Task { await refreshIfStale() }
            }
    }

    private func refreshIfStale() async {
        guard let dataDate else {
            // Nothing on screen at all: keep trying, this is how a page that
            // opened offline recovers on its own.
            await refresh()
            return
        }
        guard Date().timeIntervalSince(dataDate) > ttl else { return }
        await refresh()
    }
}

extension View {
    /// Refresh this page whenever what it shows is older than `ttl`.
    /// - Parameters:
    ///   - ttl: how long the data stays good — see `Freshness`.
    ///   - since: when the displayed data was produced; nil when there is none.
    ///   - refresh: the page's own load, which is expected to guard reentrancy.
    func refreshWhenStale(ttl: TimeInterval, since: Date?,
                          refresh: @escaping () async -> Void) -> some View {
        modifier(RefreshWhenStale(ttl: ttl, dataDate: since, refresh: refresh))
    }
}
