import SwiftUI
import UIKit

/// The iPhone/iPad app. Same settings tabs as the Mac, minus Claude usage —
/// that one reads Claude Code's Keychain via the `security` CLI, which iOS has
/// no equivalent for.
///
/// Config doesn't sync automatically between the Mac and here: an App Group is
/// per-device. Use the Config tab's export on one and import on the other.
@main
struct MyWidgetsPhoneApp: App {
    var body: some Scene {
        WindowGroup {
            PhoneRootView()
                // Widget taps land here — hand web URLs to Safari.
                .onOpenURL { url in
                    if url.scheme == "https" || url.scheme == "http" {
                        UIApplication.shared.open(url)
                    }
                }
        }
    }
}

struct PhoneRootView: View {
    var body: some View {
        TabView {
            tab(GrafanaSettingsView(), "Grafana", "chart.xyaxis.line")
            tab(WindguruSettingsView(), "Windguru", "wind")
            tab(CamSettingsView(), "Webcams", "video")
            tab(ConfigSettingsView(), "Config", "arrow.up.arrow.down.circle")
        }
    }

    /// Each tab gets its own navigation stack so the title stays put while the
    /// form scrolls, and so an iPad shows them side by side sensibly.
    private func tab<V: View>(_ view: V, _ title: String, _ icon: String) -> some View {
        NavigationStack {
            view
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
        }
        .tabItem { Label(title, systemImage: icon) }
    }
}
