import Foundation
import SwiftUI

/// Shared identifier for the App Group container the fetcher writes into.
enum AppConstants {
    static let appGroup = BuildConfig.appGroup
    static let fileName = "usage.json"
}

// MARK: - Decoded snapshot

struct Snapshot: Codable {
    var generatedAt: String
    var accounts: [Account]
    var source: String?   // "app" (default) or "widget" (self-fetched)

    var generatedDate: Date? { ISO8601.parse(generatedAt) }
}

struct Account: Codable, Identifiable {
    var id: String
    var cli: String
    var loggedIn: Bool
    var email: String?
    var org: String?
    var plan: String?
    var label: String?
    var error: String?
    var fiveHour: QuotaGauge
    var week: QuotaGauge
    var fable: QuotaGauge
    var activeKind: String?

    /// Short status chip for error states (kept tiny to fit the identity column).
    var statusText: String? {
        switch error {
        case nil: return nil
        case "logged_out": return "logged out"
        case "no_token": return "no token"
        case "session_expired": return "expired · log in"
        case "token_expired": return "expired · log in"
        default: return error
        }
    }

    var needsAttention: Bool { error != nil }

    /// Friendly label per account — configured in the app's Accounts settings.
    var displayName: String { label ?? org ?? cli }

    /// The single headline number used to rank "which account to use":
    /// the worst (highest) of the three quotas that actually have data.
    var worstPercent: Int {
        [fiveHour.percent, week.percent, fable.percent].compactMap { $0 }.max() ?? 0
    }
}

struct QuotaGauge: Codable {
    var percent: Int?
    var severity: String?   // "normal" | "warning" | "critical"
    var resetsAt: String?

    var fraction: Double { Double(percent ?? 0) / 100.0 }

    var color: Color {
        switch severity {
        case "critical": return .red
        case "warning": return .orange
        default:
            // Fall back to threshold colouring when severity is plain "normal".
            switch percent ?? 0 {
            case ..<70: return .green
            case ..<90: return .orange
            default: return .red
            }
        }
    }

    var resetDate: Date? { resetsAt.flatMap(ISO8601.parse) }
}

// MARK: - ISO8601 helper (handles fractional seconds + offset)

enum ISO8601 {
    static let withFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    static func parse(_ s: String?) -> Date? {
        guard let s else { return nil }
        return withFractional.date(from: s) ?? plain.date(from: s)
    }
}

// MARK: - Loading

enum UsageStore {
    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroup)?
            .appendingPathComponent(AppConstants.fileName)
    }

    static func load() -> Snapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    /// Write into the App Group container atomically.
    @discardableResult
    static func save(_ snapshot: Snapshot) -> Bool {
        guard let url = fileURL,
              let data = try? JSONEncoder().encode(snapshot) else { return false }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tmp = url.appendingPathExtension("tmp")
        do {
            try data.write(to: tmp, options: .atomic)
            _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmp)
            return true
        } catch {
            return false
        }
    }

    /// A friendly relative age string for "generated N min ago".
    static func ageText(from date: Date?, now: Date = Date()) -> String {
        guard let date else { return "no data" }
        let secs = Int(now.timeIntervalSince(date))
        if secs < 60 { return "just now" }
        if secs < 3600 { return "\(secs / 60)m ago" }
        return "\(secs / 3600)h ago"
    }
}

extension Snapshot {
    /// Preserve last-good gauges for accounts whose fresh fetch hit a *transient*
    /// error (rate-limit / 5xx / network), so blips don't blank real numbers.
    /// Hard states (logged_out, token_expired) are shown as-is.
    func mergingTransientErrors(with old: Snapshot?) -> Snapshot {
        guard let old else { return self }
        func transient(_ e: String?) -> Bool {
            guard let e else { return false }
            return e == "http_429" || e == "http_0" || e.hasPrefix("http_5")
        }
        var merged = self
        merged.accounts = accounts.map { n in
            if transient(n.error),
               let o = old.accounts.first(where: { $0.id == n.id }), o.error == nil {
                return o
            }
            return n
        }
        return merged
    }
}

/// Placeholder snapshot for previews / gallery.
extension Snapshot {
    static let placeholder = Snapshot(
        generatedAt: "2026-07-23T18:13:00+00:00",
        accounts: [
            Account(id: "personal", cli: "claude", loggedIn: true, email: "you@example.com",
                    org: "Personal", plan: "max", label: "Personal", error: nil,
                    fiveHour: QuotaGauge(percent: 41, severity: "normal", resetsAt: nil),
                    week: QuotaGauge(percent: 9, severity: "normal", resetsAt: nil),
                    fable: QuotaGauge(percent: 0, severity: "normal", resetsAt: nil),
                    activeKind: "session"),
            Account(id: "work", cli: "claudec", loggedIn: true, email: "you@work.com",
                    org: "Work", plan: "team", label: "Work", error: nil,
                    fiveHour: QuotaGauge(percent: 0, severity: "normal", resetsAt: nil),
                    week: QuotaGauge(percent: 100, severity: "critical", resetsAt: nil),
                    fable: QuotaGauge(percent: 29, severity: "normal", resetsAt: nil),
                    activeKind: "weekly_all"),
        ]
    )
}
