// macOS only: reads Claude Code credentials by running the `security` CLI,
// which iOS has no equivalent for.
#if os(macOS)
import Foundation

/// Claude usage fetcher — the "weather widget" pattern: reads tokens from the
/// Claude Code CLI's Keychain items (via /usr/bin/security, which the user
/// has Always-Allowed) and queries the OAuth usage endpoint. Used by both the
/// app (5-min timer) and the widget (self-fetch when the snapshot is stale).
///
/// Accounts are configurable — see AccountsConfig.
enum SelfFetch {

    // MARK: - Raw API response (subset we need)

    struct RawUsage: Decodable {
        struct Window: Decodable { var utilization: Double?; var resets_at: String? }
        struct Scope: Decodable { var model: Model? }
        struct Model: Decodable { var display_name: String? }
        struct Limit: Decodable {
            var kind: String?
            var percent: Double?
            var severity: String?
            var resets_at: String?
            var is_active: Bool?
            var scope: Scope?
        }
        var five_hour: Window?
        var seven_day: Window?
        var limits: [Limit]?
    }

    // MARK: - Keychain via /usr/bin/security

    /// What Claude Code stores: a short-lived access token plus its expiry.
    /// The access token is good for about 8 hours; Claude Code renews it from its
    /// refresh token whenever it next talks to the API. Nothing else renews it,
    /// so between Claude Code sessions it simply lapses.
    struct Credential {
        let token: String
        let expiresAt: Date?

        /// Treated as expired a minute early, so a token that dies mid-request
        /// doesn't produce a confusing 401.
        var isExpired: Bool {
            guard let expiresAt else { return false }
            return expiresAt.timeIntervalSinceNow < 60
        }
    }

    static func credential(for service: String) -> Credential? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", service, "-w"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = obj["claudeAiOauth"] as? [String: Any],
            let tok = oauth["accessToken"] as? String, !tok.isEmpty
        else { return nil }
        // expiresAt is epoch milliseconds.
        let expiry = (oauth["expiresAt"] as? NSNumber)
            .map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        return Credential(token: tok, expiresAt: expiry)
    }

    // MARK: - Usage endpoint

    static func usage(token: String) -> (Int, RawUsage?) {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.timeoutInterval = 15

        let sem = DispatchSemaphore(value: 0)
        var status = 0
        var raw: RawUsage?
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200, let data { raw = try? JSONDecoder().decode(RawUsage.self, from: data) }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 20)
        return (status, raw)
    }

    // MARK: - Distill

    static func distill(_ u: RawUsage) -> (QuotaGauge, QuotaGauge, QuotaGauge, String?) {
        let limits = u.limits ?? []
        func gauge(_ l: RawUsage.Limit?, fallback: RawUsage.Window?) -> QuotaGauge {
            if let l {
                return QuotaGauge(percent: l.percent.map { Int($0.rounded()) },
                                  severity: l.severity ?? "normal",
                                  resetsAt: l.resets_at)
            }
            return QuotaGauge(percent: fallback?.utilization.map { Int($0.rounded()) },
                              severity: "normal", resetsAt: fallback?.resets_at)
        }
        let five = gauge(limits.first { $0.kind == "session" }, fallback: u.five_hour)
        let week = gauge(limits.first { $0.kind == "weekly_all" }, fallback: u.seven_day)
        let fable = limits.first { $0.kind == "weekly_scoped" && $0.scope?.model?.display_name == "Fable" }
            .map { gauge($0, fallback: nil) }
            ?? QuotaGauge(percent: nil, severity: "normal", resetsAt: nil)
        let active = limits.first { $0.is_active == true }?.kind
        return (five, week, fable, active)
    }

    // MARK: - Full refresh

    /// Fetch all configured accounts, carrying identity labels over from
    /// `previous`. Returns nil only if nothing could be fetched at all.
    static func refresh(previous: Snapshot?) -> Snapshot? {
        var accounts: [Account] = []
        var anySuccess = false

        for spec in AccountsConfig.load() {
            let old = previous?.accounts.first { $0.id == spec.id }
            var acc = Account(
                id: spec.id, cli: spec.cli, loggedIn: false,
                email: old?.email, org: old?.org, plan: old?.plan, label: spec.label,
                error: nil,
                fiveHour: QuotaGauge(percent: nil, severity: "normal", resetsAt: nil),
                week: QuotaGauge(percent: nil, severity: "normal", resetsAt: nil),
                fable: QuotaGauge(percent: nil, severity: "normal", resetsAt: nil),
                activeKind: nil)

            guard let cred = credential(for: spec.keychainService) else {
                acc.error = old?.error == nil && old != nil ? "session_expired" : "logged_out"
                accounts.append(acc)
                continue
            }
            // Don't spend a request on a token we can already see has lapsed —
            // it would come back 401 and read as "log in again", when in fact
            // any Claude Code command will renew it.
            if cred.isExpired {
                acc.error = "token_stale"
                accounts.append(acc)
                continue
            }
            let (status, raw) = usage(token: cred.token)
            switch (status, raw) {
            case (200, .some(let u)):
                let (five, week, fable, active) = distill(u)
                acc.loggedIn = true
                acc.fiveHour = five; acc.week = week; acc.fable = fable
                acc.activeKind = active
                anySuccess = true
            case (401, _):
                acc.error = "session_expired"
            default:
                // Transient (429/5xx/network): keep the old row wholesale.
                if let old { accounts.append(old); continue }
                acc.error = "http_\(status)"
            }
            accounts.append(acc)
        }

        guard anySuccess || previous == nil else { return nil }
        return Snapshot(generatedAt: ISO8601.plain.string(from: Date()),
                        accounts: accounts, source: "widget")
    }
}

#endif
