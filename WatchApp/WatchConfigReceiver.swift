import Foundation
import WatchConnectivity
import WidgetKit

extension Notification.Name {
    /// Posted after a config push from the phone has been written, so pages
    /// that are already on screen rebuild against the new sources.
    static let watchConfigApplied = Notification.Name("watchConfigApplied")
}

/// Receives the phone's config and writes it into this device's own App Group
/// container — App Group containers do not sync across devices, so the push is
/// what stands in for the phone's files. After that, ConfigStore behaves
/// exactly as it does everywhere else and the complications read the same JSON.
final class WatchConfigReceiver: NSObject, WCSessionDelegate {
    static let shared = WatchConfigReceiver()

    private override init() { super.init() }

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        // A context sent while this app wasn't running is waiting here.
        apply(session.receivedApplicationContext)
    }

    func session(_ session: WCSession,
                 didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(applicationContext)
    }

    private func apply(_ context: [String: Any]) {
        guard let data = context["config"] as? Data,
              let bundle = try? ConfigBundle.decoded(data),
              bundle.apply()
        else { return }
        WidgetCenter.shared.reloadAllTimelines()
        // The complication picker's entries are named after the sources, so a
        // config push may have renamed them.
        WidgetCenter.shared.invalidateConfigurationRecommendations()
        NotificationCenter.default.post(name: .watchConfigApplied, object: nil)
    }
}
