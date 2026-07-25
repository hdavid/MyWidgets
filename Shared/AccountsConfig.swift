import Foundation

/// One configurable Claude account: how to find its token in the Keychain and
/// how to present it. Edited in the app's Accounts settings, read by both the
/// app and the widget (via the shared App Group container).
struct AccountSpec: Codable, Identifiable, Equatable {
    var id: String
    var label: String            // friendly name shown in widget/panel
    var cli: String              // CLI command name (informational, e.g. "claude")
    var keychainService: String  // Keychain generic-password service name

    init(id: String = UUID().uuidString, label: String, cli: String, keychainService: String) {
        self.id = id
        self.label = label
        self.cli = cli
        self.keychainService = keychainService
    }
}

enum AccountsConfig {
    static let fileName = "accounts.json"

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroup)?
            .appendingPathComponent(fileName)
    }

    /// Out of the box: the single default Claude Code login.
    static let defaultSpecs = [
        AccountSpec(id: "default", label: "Personal", cli: "claude",
                    keychainService: "Claude Code-credentials")
    ]

    static func load() -> [AccountSpec] {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let specs = try? JSONDecoder().decode([AccountSpec].self, from: data),
              !specs.isEmpty else { return defaultSpecs }
        return specs
    }

    @discardableResult
    static func save(_ specs: [AccountSpec]) -> Bool {
        guard let url = fileURL else { return false }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(specs) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}
