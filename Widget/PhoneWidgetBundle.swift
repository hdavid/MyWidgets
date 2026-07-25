import WidgetKit
import SwiftUI

/// The iOS/iPadOS widget set — everything that fetches over the network. Claude
/// usage is absent by necessity: it reads Claude Code's Keychain items via the
/// `security` CLI, which a phone doesn't have.
@main
struct PhoneWidgetBundle: WidgetBundle {
    var body: some Widget {
        MetricsWidget()
        ForecastWidget()
        WebcamWidget()
    }
}
