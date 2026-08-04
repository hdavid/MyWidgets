import SwiftUI

/// The watch companion. Deliberately configuration-free: everything it shows
/// is driven by the config the iPhone app pushes over (WatchConfigReceiver),
/// and each section is one vertical page — wind first, then forecast spots,
/// then webcams — mirroring the phone app's tabs.
@main
struct MyWidgetsWatchApp: App {
    @StateObject private var model = WatchModel()

    init() {
        WatchConfigReceiver.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
    }
}

/// The configured sections, reloaded whenever the phone pushes new config.
@MainActor
final class WatchModel: ObservableObject {
    @Published var sources: [GrafanaSource] = GrafanaConfig.load()
    @Published var spots: [WindguruSpot] = WindguruConfig.load()
    @Published var cams: [CamSpec] = CamsConfig.load()

    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .watchConfigApplied, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    func reload() {
        sources = GrafanaConfig.load()
        spots = WindguruConfig.load()
        cams = CamsConfig.load()
    }
}

struct RootView: View {
    @ObservedObject var model: WatchModel

    var body: some View {
        TabView {
            ForEach(model.sources) { source in
                WatchWindPage(source: source)
            }
            ForEach(model.spots.filter(\.isConfigured)) { spot in
                WatchForecastPage(spot: spot)
            }
            ForEach(model.cams.filter(\.isConfigured)) { cam in
                WatchCamPage(cam: cam)
            }
        }
        .tabViewStyle(.verticalPage)
    }
}
