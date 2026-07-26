import WidgetKit
import SwiftUI
import ImageIO

// MARK: - Fetch + cache
//
// The spec is read from the shared config at fetch time (Shared/CamsConfig.swift),
// so editing a webcam in the app changes what an already-placed widget shows.

struct CamEntry: TimelineEntry {
    let date: Date
    let spec: CamSpec?
    let image: CGImage?
    let capturedAt: Date?
    let stale: Bool
}

enum CamFetch {
    static func cacheURL(_ spec: CamSpec) -> URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("cam_\(spec.id).jpg")
    }

    static func fetch(_ spec: CamSpec) async -> (Data, Date?)? {
        guard let url = spec.image else { return nil }
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 15
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              data.count > 1000 else { return nil }
        var captured: Date?
        if let lm = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Last-Modified") {
            let f = DateFormatter()
            f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            f.locale = Locale(identifier: "en_US_POSIX")
            captured = f.date(from: lm)
        }
        return (data, captured)
    }

    /// Decode at reduced size — a webcam frame can be 3040×1710 and widget
    /// extensions have a tight memory ceiling; never decode full-res.
    ///
    /// 800 rather than 1400: the widest family this draws into is 344 pt, which
    /// is 688 px on a 2x display, so 1400 was roughly five times the pixels any
    /// of them can show. That surplus is not free — the frame goes into the
    /// timeline archive that the widget HOST process decodes and draws on every
    /// render pass, and it took those archives to 1.2 MB. chronod said so
    /// itself: "Filtered image [28: 1400-788]: exit (no size constraints
    /// configured)".
    static func downsample(_ data: Data, maxPixel: CGFloat = 800) -> CGImage? {
        let opts = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true
        ] as CFDictionary
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts)
    }

    static func entry(_ camID: String?) async -> CamEntry {
        guard let spec = CamsConfig.spec(camID) else {
            return CamEntry(date: Date(), spec: nil, image: nil, capturedAt: nil, stale: true)
        }
        if let (data, captured) = await fetch(spec) {
            try? data.write(to: cacheURL(spec))
            let at = captured ?? Date()
            UserDefaults.standard.set(at.timeIntervalSince1970, forKey: "cam_\(spec.id)_capturedAt")
            return CamEntry(date: Date(), spec: spec, image: downsample(data),
                            capturedAt: at, stale: false)
        }
        // Network/server problem: show the last cached frame, marked offline.
        if let data = try? Data(contentsOf: cacheURL(spec)) {
            let t = UserDefaults.standard.double(forKey: "cam_\(spec.id)_capturedAt")
            return CamEntry(date: Date(), spec: spec, image: downsample(data),
                            capturedAt: t > 0 ? Date(timeIntervalSince1970: t) : nil,
                            stale: true)
        }
        return CamEntry(date: Date(), spec: spec, image: nil, capturedAt: nil, stale: true)
    }
}

// MARK: - Provider

struct CamProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CamEntry {
        CamEntry(date: Date(), spec: CamsConfig.load().first,
                 image: nil, capturedAt: nil, stale: false)
    }

    func snapshot(for configuration: SelectCamIntent, in context: Context) async -> CamEntry {
        await CamFetch.entry(configuration.cam?.id)
    }

    func timeline(for configuration: SelectCamIntent, in context: Context) async -> Timeline<CamEntry> {
        let entry = await CamFetch.entry(configuration.cam?.id)
        let after = entry.spec?.refreshInterval ?? 300
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(after)))
    }
}

// MARK: - View

struct CamView: View {
    var entry: CamEntry

    var body: some View {
        HStack(spacing: 4) {
            Text(entry.spec?.name ?? "Webcam")
                .fontWeight(.semibold)
            if let c = entry.capturedAt {
                Text(timeText(c))
                    .foregroundStyle(captionAgeColor(c))
            }
            if entry.stale {
                Text("· offline")
                    .foregroundStyle(Color(hex: "#ff6b5e"))
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.black.opacity(0.45), in: Capsule())
        .opacity(entry.image == nil ? 0 : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .widgetURL(entry.spec?.page)
        .containerBackground(for: .widget) {
            if let img = entry.image {
                Image(decorative: img, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Pal.bg
                    VStack(spacing: 6) {
                        Image(systemName: entry.spec?.isConfigured == true
                              ? "video.slash" : "gearshape")
                            .font(.title2)
                        Text(entry.spec?.isConfigured == true
                             ? "No image"
                             : "Add a webcam in the app’s Webcams tab")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(Pal.gray)
                    .padding(8)
                }
            }
        }
    }

    /// On a photo the caption is always white-on-dark; only the time tints
    /// when the frame is getting old.
    private func captionAgeColor(_ at: Date) -> Color {
        let ageMin = Date().timeIntervalSince(at) / 60
        if ageMin > 30 { return Color(hex: "#ff6b5e") }
        if ageMin > 10 { return Color(hex: "#ffb340") }
        return .white
    }
}

// MARK: - Widget
//
// One kind, added as many times as you like — each copy picks its webcam.

struct WebcamWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Webcam", intent: SelectCamIntent.self,
                               provider: CamProvider()) { entry in
            CamView(entry: entry)
        }
        .configurationDisplayName("Webcam")
        .description("Latest frame from a webcam. Right-click → Edit Widget to pick which one.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
