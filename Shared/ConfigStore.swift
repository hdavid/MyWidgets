import Foundation

/// Resolves where the config JSON files live, and reads them.
///
/// Three sources, in order:
///
///  1. **App Group container** — the normal case. The app writes the files and
///     the widget extension reads the very same ones, so edits show up in
///     widgets. Requires the App Groups capability.
///  2. **The process's own container** — used when there is no App Group, which
///     is the case on a free personal Apple team (the capability isn't offered).
///     The app can save and reload its own settings, but the widget extension
///     gets a *separate* sandbox and would otherwise see nothing at all.
///  3. **Config bundled into the app at build time** — read-only, and the only
///     thing that crosses the app/extension boundary without an App Group: an
///     extension may read resources from the app bundle it is embedded in. This
///     is what lets widgets render real values in a no-App-Group build.
///
/// So on a free team the app is editable-but-private and the widgets are
/// real-but-frozen at whatever was bundled. `isShared` reports which mode is in
/// effect so the UI can say so rather than looking broken.
enum ConfigStore {
    /// Directory inside the bundle holding the build-time config copy.
    private static let bundledDirectory = "BundledConfig"

    /// True when the App Group container is reachable, i.e. app and widget share
    /// one set of files and edits reach the widgets.
    static var isShared: Bool { groupContainer != nil }

    /// True when the only config available is the read-only bundled copy — the
    /// situation a widget extension is in without an App Group.
    static var isBundledOnly: Bool {
        groupContainer == nil && privateContainerHasConfig == false
    }

    private static var groupContainer: URL? {
        guard !BuildConfig.appGroup.isEmpty else { return nil }
        return FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: BuildConfig.appGroup)
    }

    /// Per-process fallback. Not shared with the widget extension — each gets its
    /// own sandbox — which is why it is the fallback and not the default.
    private static var privateContainer: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory,
                                     in: .userDomainMask,
                                     appropriateFor: nil, create: true)
    }

    private static var privateContainerHasConfig: Bool {
        guard let dir = privateContainer else { return false }
        return FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("grafana.json").path)
    }

    /// Where a file is read from and written to. Nil only if neither container
    /// can be resolved.
    static func url(_ fileName: String) -> URL? {
        (groupContainer ?? privateContainer)?.appendingPathComponent(fileName)
    }

    /// Create the containing directory, then hand back the URL to write to.
    static func writeURL(_ fileName: String) -> URL? {
        guard let url = url(fileName) else { return nil }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return url
    }

    /// Read a config file, falling back to the copy bundled at build time.
    static func read(_ fileName: String) -> Data? {
        if let url = url(fileName), let data = try? Data(contentsOf: url) {
            return data
        }
        return bundled(fileName)
    }

    /// The build-time copy inside the app bundle.
    ///
    /// For a widget extension `Bundle.main` is the .appex, which has no copy of
    /// its own, so walk up to the containing app bundle — `Foo.app/PlugIns/X.appex`
    /// → `Foo.app`. That read is permitted: it is still the app's own bundle.
    private static func bundled(_ fileName: String) -> Data? {
        let name = (fileName as NSString).deletingPathExtension
        if let url = Bundle.main.url(forResource: name, withExtension: "json",
                                     subdirectory: bundledDirectory),
           let data = try? Data(contentsOf: url) {
            return data
        }
        let containing = Bundle.main.bundleURL
            .deletingLastPathComponent()   // PlugIns/
            .deletingLastPathComponent()   // Foo.app/
        for candidate in ["Contents/Resources/\(bundledDirectory)", bundledDirectory] {
            let url = containing
                .appendingPathComponent(candidate)
                .appendingPathComponent(fileName)
            if let data = try? Data(contentsOf: url) { return data }
        }
        return nil
    }
}
