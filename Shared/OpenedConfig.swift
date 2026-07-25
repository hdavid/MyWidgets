import Foundation
import WidgetKit

/// Handles a config file handed to the app from outside — double-clicked in
/// Finder, opened from the Files app, or sent through the share sheet.
///
/// The app owns the `.mywidgets` type (see the Info.plist declarations), so the
/// system routes such a file here; this turns that into an applied import and a
/// message the Config tab can show.
@MainActor
final class OpenedConfig: ObservableObject {
    static let shared = OpenedConfig()

    @Published private(set) var message: String?
    @Published private(set) var failed = false

    private init() {}

    /// True when this URL is a config file we should import rather than a web
    /// link to hand to the browser.
    static func isConfigFile(_ url: URL) -> Bool {
        url.isFileURL
    }

    func `import`(_ url: URL) {
        // A URL arriving from outside the sandbox has to be opened through its
        // security scope before it can be read.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        do {
            let bundle = try ConfigBundle.decoded(try Data(contentsOf: url))
            guard bundle.apply() else {
                report("Read “\(url.lastPathComponent)”, but could not write the config.",
                       failed: true)
                return
            }
            WidgetCenter.shared.reloadAllTimelines()
            report("Imported “\(url.lastPathComponent)” ✓ — \(bundle.summary).", failed: false)
        } catch {
            report("Could not import “\(url.lastPathComponent)”: \(error.localizedDescription)",
                   failed: true)
        }
    }

    private func report(_ text: String, failed: Bool) {
        message = text
        self.failed = failed
    }
}
