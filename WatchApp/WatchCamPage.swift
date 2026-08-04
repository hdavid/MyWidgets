import SwiftUI
import ImageIO

/// One webcam, full-bleed, with the same name + capture-time caption the
/// widget draws. Tap to refetch.
struct WatchCamPage: View {
    var cam: CamSpec

    @State private var image: CGImage?
    @State private var capturedAt: Date?
    @State private var stale = false
    @State private var loading = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let image {
                GeometryReader { geo in
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
                .ignoresSafeArea()
                HStack(spacing: 4) {
                    Text(cam.name)
                        .fontWeight(.semibold)
                    if let capturedAt {
                        Text(timeText(capturedAt))
                    }
                    if stale {
                        Text("· offline")
                            .foregroundStyle(Color(hex: "#ff6b5e"))
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.black.opacity(0.45), in: Capsule())
                .padding(6)
            } else {
                NoDataView(message: loading ? "Loading…" : "No image from \(cam.name)")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { Task { await load() } }
        .task(id: cam) { await load() }
    }

    private func load() async {
        guard !loading, let url = cam.image else { return }
        loading = true
        defer { loading = false }
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 15
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              data.count > 1000,
              let img = downsample(data)
        else {
            stale = image != nil
            return
        }
        image = img
        stale = false
        capturedAt = lastModified(resp) ?? Date()
    }

    /// A webcam frame can be 3040×1710; a watch never needs more than its own
    /// screen width, and decoding full-res would blow the memory budget.
    private func downsample(_ data: Data, maxPixel: CGFloat = 480) -> CGImage? {
        let opts = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true
        ] as CFDictionary
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts)
    }

    private func lastModified(_ resp: URLResponse) -> Date? {
        guard let lm = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Last-Modified") else { return nil }
        let f = DateFormatter()
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: lm)
    }
}
