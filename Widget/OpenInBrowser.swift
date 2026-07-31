import SwiftUI
import WidgetKit
import AppIntents

/// A click that lands in the browser instead of in our app.
///
/// `widgetURL` is defined as "open this URL *in the containing app*", so it
/// always wakes MyWidgets first and the app then forwards the link on — a
/// visible bounce through the Dock for something the system can do itself.
///
/// The obvious shortcut, hanging `OpenURLIntent` straight off the button, does
/// not work: a widget button's intent is resolved by identifier against the
/// bundle's `Metadata.appintents`, and the build-time extractor only records
/// intents *we declare* — a framework type we merely reference is never in
/// there. chronod says as much when clicked:
///
///     Started executing LNAction OpenURLIntent … from widget
///     linkd: Missing: systems.holonic.MyWidgets:OpenURLIntent
///     Failed to execute LNAction … There is no metadata for OpenURLIntent
///
/// So the button runs an intent of ours, which the extractor does record, and
/// that intent hands `OpenURLIntent` back as the thing to open next. The
/// *system* performs it, so neither the extension nor the app opens the link.
/// `result(opensIntent:)` goes back to macOS 13; only `OpenURLIntent` itself
/// needs macOS 15 / iOS 18, hence the `widgetURL` fallback below that.
@available(macOS 15.0, iOS 18.0, *)
struct OpenPageIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Page"
    static var description = IntentDescription("Opens a widget's page in the browser.")
    /// The system does the opening; we must not be brought to the front for it.
    static var openAppWhenRun = false

    @Parameter(title: "URL")
    var url: URL

    init() {}
    init(url: URL) { self.url = url }

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(url))
    }
}

extension View {
    @ViewBuilder
    func opensInBrowser(_ url: URL?) -> some View {
        if let url {
            if #available(macOS 15.0, iOS 18.0, *) {
                // The label has to claim the whole widget, otherwise only the
                // area the content happens to occupy is clickable.
                Button(intent: OpenPageIntent(url: url)) {
                    frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)
            } else {
                widgetURL(url)
            }
        } else {
            self
        }
    }
}
