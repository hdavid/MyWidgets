#if os(iOS)
import Foundation
import WatchConnectivity

/// Pushes the phone's config to the watch companion. The watch has no config
/// UI at all — this push is the only way settings reach it.
///
/// The channel is `updateApplicationContext`, which fits config exactly:
/// latest-wins (an old bundle is never delivered after a newer one), queued
/// until the watch is reachable, and redelivered after the watch app is
/// reinstalled. Tokens are included on purpose: the watch fetches Grafana
/// itself, and WatchConnectivity is a private device-to-device channel, not an
/// export file that could end up in a mail attachment.
final class PhoneWatchSync: NSObject, WCSessionDelegate {
    static let shared = PhoneWatchSync()

    private override init() { super.init() }

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Encode the whole current config and hand it over. Safe to call often:
    /// identical contexts are deduplicated by the session, and an inactive or
    /// watchless session is simply skipped.
    func push() {
        let session = WCSession.default
        guard WCSession.isSupported(),
              session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled,
              let data = try? ConfigBundle.current(includeTokens: true).encoded()
        else { return }
        try? session.updateApplicationContext(["config": data])
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        if activationState == .activated { push() }
    }

    /// Pairing or install state changed — a freshly installed watch app should
    /// not have to wait for the next config edit.
    func sessionWatchStateDidChange(_ session: WCSession) {
        push()
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Switching to a new watch deactivates the session; reactivate for it.
        session.activate()
    }
}
#endif
