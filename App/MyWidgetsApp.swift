import SwiftUI
import WidgetKit
#if os(macOS)
import ServiceManagement
#else
import UIKit
#endif

/// One app for macOS, iOS and iPadOS. The settings tabs are shared; what differs
/// is the shell around them (a resizable window plus a menu-bar panel on the Mac,
/// a plain scene on the phone) and Claude usage, which only a Mac can read.
@main
struct MyWidgetsApp: App {
    #if os(macOS)
    @StateObject private var model = UsageAppModel()
    #endif

    var body: some Scene {
        #if os(macOS)
        // A real window (Dock icon, double-clickable) …
        Window("My Widgets", id: "main") {
            MainWindowView(model: model)
                .onOpenURL(perform: openExternally)
        }
        .windowResizability(.contentSize)

        // … plus the menu-bar panel for quick glances at Claude usage.
        MenuBarExtra {
            PanelView(model: model)
        } label: {
            if let best = model.snapshot.flatMap({ Ranking.best($0.accounts) }) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                Text(best.cli)
            } else {
                Image(systemName: "gauge.with.dots.needle.100percent")
            }
        }
        .menuBarExtraStyle(.window)
        #else
        WindowGroup {
            MainWindowView()
                .onOpenURL(perform: openExternally)
        }
        #endif
    }

    /// Widget clicks land in the app — hand web URLs straight to the browser.
    private func openExternally(_ url: URL) {
        guard url.scheme == "https" || url.scheme == "http" else { return }
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }
}

// MARK: - Main window / root view

struct MainWindowView: View {
    #if os(macOS)
    @ObservedObject var model: UsageAppModel
    #endif

    var body: some View {
        // Claude usage summary intentionally NOT in the window — the menu-bar
        // panel and the widget already show it.
        #if os(macOS)
        TabView {
            GrafanaSettingsView()
                .tabItem { Label("Grafana", systemImage: "chart.xyaxis.line") }
            WindguruSettingsView()
                .tabItem { Label("Windguru", systemImage: "wind") }
            CamSettingsView()
                .tabItem { Label("Webcams", systemImage: "video") }
            AccountSettingsView(model: model)
                .tabItem { Label("Claude", systemImage: "person.2") }
            ConfigSettingsView()
                .tabItem { Label("Config", systemImage: "arrow.up.arrow.down.circle") }
        }
        // Tabs are shorter than the window; without this a short tab's content
        // floats in the vertical centre instead of sitting under the tab bar.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(12)
        .frame(width: 620, height: 620)
        #else
        TabView {
            phoneTab(GrafanaSettingsView(), "Grafana", "chart.xyaxis.line")
            phoneTab(WindguruSettingsView(), "Windguru", "wind")
            phoneTab(CamSettingsView(), "Webcams", "video")
            phoneTab(ConfigSettingsView(), "Config", "arrow.up.arrow.down.circle")
        }
        #endif
    }

    #if !os(macOS)
    /// Each tab gets its own navigation stack so the title stays put while the
    /// form scrolls, and so an iPad lays them out sensibly.
    private func phoneTab<V: View>(_ view: V, _ title: String, _ icon: String) -> some View {
        NavigationStack {
            view
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
        }
        .tabItem { Label(title, systemImage: icon) }
    }
    #endif
}

#if os(macOS)

// MARK: - Model (fetch engine + timer + login item)
//
// macOS only: reading a Claude Code credential means running the `security` CLI,
// which iOS has no equivalent for.

@MainActor
final class UsageAppModel: ObservableObject {
    @Published var snapshot: Snapshot? = UsageStore.load()
    @Published var refreshing = false
    @Published var lastError: String?

    private var timer: Timer?

    init() {
        registerLoginItem()
        refresh()  // honors the freshness guard below
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Launch at login so the usage widget stays fresh without opening anything.
    private func registerLoginItem() {
        do {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } catch {
            // Non-fatal: the app still works while running.
            lastError = "login-item: \(error.localizedDescription)"
        }
    }

    /// Refresh Claude usage. `force` bypasses the freshness guard (used by
    /// the Refresh button); automatic calls skip if data is < 2 min old, so we
    /// never hammer the usage endpoint (which rate-limits with HTTP 429).
    func refresh(force: Bool = false) {
        guard !refreshing else { return }
        if !force, let g = snapshot?.generatedDate, Date().timeIntervalSince(g) < 120 { return }
        refreshing = true
        lastError = nil
        let previous = snapshot
        Task.detached(priority: .userInitiated) {
            let fresh = SelfFetch.refresh(previous: previous)
            await MainActor.run {
                self.refreshing = false
                guard let fresh else {
                    self.lastError = "could not fetch any account"
                    return
                }
                let merged = fresh.mergingTransientErrors(with: previous)
                if UsageStore.save(merged) {
                    self.snapshot = merged
                    WidgetCenter.shared.reloadTimelines(ofKind: "ClaudeUsageWidget")
                } else {
                    self.lastError = "could not save snapshot"
                }
            }
        }
    }
}

// MARK: - Claude usage panel (menu bar)

struct PanelView: View {
    @ObservedObject var model: UsageAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let snap = model.snapshot {
                let bestID = Ranking.bestAccountID(snap.accounts)
                ColumnHeader().padding(.horizontal, 6)
                VStack(spacing: 0) {
                    ForEach(Array(snap.accounts.enumerated()), id: \.element.id) { i, acc in
                        AccountRow(account: acc, isBest: acc.id == bestID)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 6)
                            .background(acc.id == bestID
                                        ? Color.green.opacity(0.10) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        if i < snap.accounts.count - 1 {
                            Divider().opacity(0.35)
                        }
                    }
                }
                HStack {
                    Text("Updated \(UsageStore.ageText(from: snap.generatedDate)) · ✓ = most headroom")
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    if model.refreshing { ProgressView().controlSize(.small) }
                    Button { model.refresh(force: true) } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless)
                        .disabled(model.refreshing)
                }
            } else {
                EmptyStateView().frame(height: 160)
                HStack {
                    Spacer()
                    Button { model.refresh(force: true) } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless)
                        .disabled(model.refreshing)
                }
            }

            if let err = model.lastError {
                Text(err).font(.caption2).foregroundStyle(.red).lineLimit(3)
            }
        }
        .padding(14)
        .frame(width: 360)
    }
}

#endif
