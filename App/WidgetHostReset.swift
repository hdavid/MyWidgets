#if os(macOS)
import Foundation

/// The macOS widget sidebar is hosted by Apple's NotificationCenter process,
/// which occasionally spins at 100% CPU inside its own SwiftUI view graph —
/// an Apple bug, sampled twice with zero MyWidgets frames (see
/// scripts/nc-watchdog.sh for the write-up). The only remedy is SIGTERM;
/// launchd relaunches NotificationCenter within a second and the fresh
/// instance sits idle, so this is non-destructive.
///
/// chronod is deliberately left alone: it is not the process that spins, and
/// repeated kills eat launchd's exponential-throttling budget, which can leave
/// widgets blank for a minute.
enum WidgetHostReset {

    /// Restart the widget sidebar host. Returns a short status line for the UI.
    static func restartSidebar() -> String {
        let pids: [pid_t]
        do {
            pids = try processIDs(named: "NotificationCenter")
        } catch {
            return "could not look up NotificationCenter: \(error.localizedDescription)"
        }
        guard !pids.isEmpty else {
            return "NotificationCenter is not running — nothing to restart"
        }
        let failed = pids.filter { kill($0, SIGTERM) != 0 }
        guard failed.isEmpty else {
            return "could not signal pid \(failed.map(String.init).joined(separator: ", "))"
        }
        return "Sidebar restarted — it respawns in a second."
    }

    /// PIDs of processes whose executable name matches `name` exactly.
    private static func processIDs(named name: String) throws -> [pid_t] {
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-x", name]
        let out = Pipe()
        pgrep.standardOutput = out
        try pgrep.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        pgrep.waitUntilExit()
        // pgrep exits 1 for "no match" — that is a valid empty result, not an error.
        guard pgrep.terminationStatus == 0 else { return [] }
        return String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .compactMap { pid_t($0) }
    }
}
#endif
