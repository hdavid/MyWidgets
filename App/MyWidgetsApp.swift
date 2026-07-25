import SwiftUI
import WidgetKit
import ServiceManagement

@main
struct MyWidgetsApp: App {
    @StateObject private var model = UsageAppModel()

    var body: some Scene {
        // A real window (Dock icon, double-clickable) …
        Window("My Widgets", id: "main") {
            MainWindowView(model: model)
                // Widget clicks land here — forward web URLs to the browser.
                .onOpenURL { url in
                    if url.scheme == "https" || url.scheme == "http" {
                        NSWorkspace.shared.open(url)
                    }
                }
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
    }
}

// MARK: - Model (fetch engine + timer + login item)

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

// MARK: - Main window (tabs: usage / accounts / widgets)

struct MainWindowView: View {
    @ObservedObject var model: UsageAppModel

    var body: some View {
        // Claude usage summary intentionally NOT in the window — the menu-bar
        // panel and the widget already show it.
        TabView {
            WidgetsInfoView()
                .tabItem { Label("Widgets", systemImage: "square.grid.2x2") }
            GrafanaSettingsView()
                .tabItem { Label("Grafana", systemImage: "chart.xyaxis.line") }
            WindguruSettingsView()
                .tabItem { Label("Windguru", systemImage: "wind") }
            CamSettingsView()
                .tabItem { Label("Webcams", systemImage: "video") }
            AccountSettingsView(model: model)
                .tabItem { Label("Claude", systemImage: "person.2") }
        }
        .padding(12)
        .frame(width: 620, height: 620)
    }
}

// MARK: - Claude usage panel (shared by window tab and menu bar)

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

// MARK: - Widgets info tab

struct WidgetsInfoView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Included widgets").font(.headline)
            Text("""
            • Live Wind — your Grafana metrics, self-updating (Grafana tab)
            • Moutiers Forecast — windguru hourly wind/gust/direction (Windguru tab)
            • Webcam 1–3 — latest frame, click to open the page (Webcams tab)
            • Claude Usage — 5h / weekly / Fable quota per account (Claude tab)

            Add them: right-click the desktop → Edit Widgets → “My Widgets”.

            Wind, forecast and webcams fetch their own data. Claude usage is \
            fetched by this app every 5 minutes (and by the widget itself when \
            stale) — the app launches at login for that.
            """)
            .font(.callout)
            .foregroundStyle(.secondary)
            Button("Reload all widgets") {
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
