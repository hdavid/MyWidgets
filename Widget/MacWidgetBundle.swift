import WidgetKit
import SwiftUI

/// The macOS widget set. Claude usage is here and not in the iOS bundle: it
/// reads Claude Code's Keychain items by shelling out to `security`, which
/// only exists on a Mac.
@main
struct MacWidgetBundle: WidgetBundle {
    var body: some Widget {
        MetricsWidget()
        ForecastWidget()
        WebcamWidget()
        ClaudeUsageWidget()
    }
}
