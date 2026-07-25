import Foundation

/// One webcam. Added and removed freely in the app's Webcams tab; a placed
/// widget stores which one it shows in its own configuration intent, so the
/// list length is not tied to anything compiled in.
struct CamSpec: Codable, Identifiable, Equatable {
    var id: String
    var name: String            // drawn on the frame
    var imageURL: String        // still image, re-fetched on every refresh
    var pageURL: String         // opened when the widget is clicked
    var refreshMinutes: Int

    init(id: String = UUID().uuidString, name: String, imageURL: String = "",
         pageURL: String = "", refreshMinutes: Int = 5) {
        self.id = id
        self.name = name
        self.imageURL = imageURL
        self.pageURL = pageURL
        self.refreshMinutes = refreshMinutes
    }

    var image: URL? { URL(string: imageURL.trimmingCharacters(in: .whitespacesAndNewlines)) }
    var page: URL? { URL(string: pageURL.trimmingCharacters(in: .whitespacesAndNewlines)) }
    var isConfigured: Bool { image != nil }
    /// Clamped so a typo can't ask WidgetKit for a one-second refresh.
    var refreshInterval: TimeInterval { TimeInterval(max(1, min(180, refreshMinutes)) * 60) }
}

enum CamsConfig {
    static let fileName = "webcams.json"

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroup)?
            .appendingPathComponent(fileName)
    }

    /// Deliberately empty of real endpoints: those belong in the App Group
    /// config (see scripts/local-config.sh), not committed to the repo.
    static let defaultSpecs = [CamSpec(id: "default", name: "Webcam")]

    static func load() -> [CamSpec] {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let specs = try? JSONDecoder().decode([CamSpec].self, from: data),
              !specs.isEmpty
        else { return defaultSpecs }
        return specs
    }

    /// The cam a widget instance is bound to, falling back to the first one so a
    /// widget placed before anything was configured still shows something.
    static func spec(_ id: String?) -> CamSpec? {
        let all = load()
        guard let id else { return all.first }
        return all.first { $0.id == id } ?? all.first
    }

    @discardableResult
    static func save(_ specs: [CamSpec]) -> Bool {
        guard let url = fileURL else { return false }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(specs) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}
