import Foundation

/// Every config file in one document, for moving a setup between machines (and
/// between Mac and iPhone). Deliberately one file rather than four: the widgets
/// only make sense together, and a partial restore is a confusing state.
struct ConfigBundle: Codable {
    /// Bumped if the shape changes incompatibly; `load` refuses newer versions
    /// rather than silently dropping fields it doesn't know.
    static let currentVersion = 1

    var version: Int
    var exportedAt: Date
    var grafana: [GrafanaSource]
    var windguru: [WindguruSpot]
    var webcams: [CamSpec]
    var accounts: [AccountSpec]

    /// Snapshot what's configured right now.
    ///
    /// `includeTokens` is opt-in because Grafana service-account tokens are
    /// bearer credentials: an export is a plain JSON file that may end up in a
    /// mail attachment or a sync folder.
    static func current(includeTokens: Bool) -> ConfigBundle {
        var sources = GrafanaConfig.load()
        if !includeTokens {
            sources = sources.map { s in
                var copy = s
                copy.token = ""
                return copy
            }
        }
        return ConfigBundle(version: currentVersion,
                            exportedAt: Date(),
                            grafana: sources,
                            windguru: WindguruConfig.load(),
                            webcams: CamsConfig.load(),
                            accounts: AccountsConfig.load())
    }

    func encoded() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return try enc.encode(self)
    }

    static func decoded(_ data: Data) throws -> ConfigBundle {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let bundle = try dec.decode(ConfigBundle.self, from: data)
        guard bundle.version <= currentVersion else {
            throw ConfigBundleError.tooNew(bundle.version)
        }
        return bundle
    }

    /// Write every section back. Tokens already present are kept when the
    /// incoming source has an empty one, so importing a token-less export onto a
    /// machine that already has its tokens doesn't wipe them.
    @discardableResult
    func apply() -> Bool {
        let existing = Dictionary(GrafanaConfig.load().map { ($0.id, $0.token) },
                                  uniquingKeysWith: { a, _ in a })
        let merged = grafana.map { s -> GrafanaSource in
            guard s.token.isEmpty, let kept = existing[s.id], !kept.isEmpty else { return s }
            var copy = s
            copy.token = kept
            return copy
        }
        var ok = true
        if !merged.isEmpty { ok = GrafanaConfig.save(merged) && ok }
        if !windguru.isEmpty { ok = WindguruConfig.save(windguru) && ok }
        if !webcams.isEmpty { ok = CamsConfig.save(webcams) && ok }
        if !accounts.isEmpty { ok = AccountsConfig.save(accounts) && ok }
        return ok
    }

    /// "2 sources · 1 spot · 3 webcams · 2 accounts"
    var summary: String {
        [count(grafana.count, "source"), count(windguru.count, "spot"),
         count(webcams.count, "webcam"), count(accounts.count, "account")]
            .joined(separator: " · ")
    }

    private func count(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }

    var tokenCount: Int { grafana.filter { !$0.token.isEmpty }.count }
}

enum ConfigBundleError: LocalizedError {
    case tooNew(Int)

    var errorDescription: String? {
        switch self {
        case .tooNew(let v):
            return "That file was written by a newer version (format \(v)) — update the app first."
        }
    }
}
