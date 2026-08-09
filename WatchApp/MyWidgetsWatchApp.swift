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
    @Published var tides: [TideLocation] = TideConfig.load()

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
        tides = TideConfig.load()
    }
}

struct RootView: View {
    @ObservedObject var model: WatchModel
    /// Page tags are "kind:id" so a complication's widgetURL
    /// (mywidgets://kind/id) can select its page directly.
    @State private var selection: String?

    var body: some View {
        TabView(selection: $selection) {
            ForEach(model.sources.filter(\.onWatch)) { source in
                WatchWindPage(source: source)
                    .tag(Optional("wind:\(source.id)"))
            }
            ForEach(model.spots.filter { $0.isConfigured && $0.onWatch }) { spot in
                WatchForecastPage(spot: spot)
                    .tag(Optional("forecast:\(spot.id)"))
            }
            ForEach(model.tides.filter(\.onWatch)) { location in
                WatchTidePage(location: location)
                    .tag(Optional("tide:\(location.id)"))
            }
            ForEach(model.cams.filter { $0.isConfigured && $0.onWatch }) { cam in
                WatchCamPage(cam: cam)
                    .tag(Optional("cam:\(cam.id)"))
            }
        }
        .tabViewStyle(.verticalPage)
        .onOpenURL { url in
            // A complication tap: mywidgets://<kind>/<id>.
            guard let kind = url.host, !url.lastPathComponent.isEmpty else { return }
            selection = "\(kind):\(url.lastPathComponent)"
        }
    }
}
