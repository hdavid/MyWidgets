import WidgetKit
import SwiftUI

/// The widget set. Two bodies rather than an `#if` inside one result builder,
/// which is the unambiguous way to vary a `WidgetBundle` by platform.
///
/// Claude usage is macOS-only: it reads Claude Code's Keychain items by shelling
/// out to `security`, which a phone doesn't have.
@main
struct MyWidgetsBundle: WidgetBundle {
    #if os(macOS)
    var body: some Widget {
        MetricsWidget()
        ForecastWidget()
        WebcamWidget()
        ClaudeUsageWidget()
    }
    #else
    var body: some Widget {
        MetricsWidget()
        ForecastWidget()
        WebcamWidget()
    }
    #endif
}
