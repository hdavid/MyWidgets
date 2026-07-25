import SwiftUI
import WidgetKit

/// Add, edit and remove webcams. Stored in the shared App Group container so the
/// widget extension reads the same values.
///
/// A placed Webcam widget remembers which entry it shows in its own
/// configuration intent (right-click → Edit Widget), so this list can be any
/// length — nothing here is tied to a compiled-in widget slot.
struct CamSettingsView: View {
    @State private var specs: [CamSpec] = CamsConfig.load()
    @State private var status: String?
    @State private var statusColor: Color = .secondary
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Webcams").font(.headline)
                Text("Point each webcam at a still image the camera overwrites (typically a “latest.jpg”); the widget re-fetches it on the interval below. The page URL is what opens when you click the widget. After adding one, right-click a Webcam widget → Edit Widget to point it at the new entry.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach($specs) { $spec in
                    camCard($spec)
                }

                HStack(spacing: 8) {
                    Button {
                        specs.append(CamSpec(name: "New webcam"))
                    } label: {
                        Label("Add webcam", systemImage: "plus")
                    }
                    if busy { ProgressView().controlSize(.small) }
                    if let status {
                        Text(status).font(.caption).foregroundStyle(statusColor)
                            .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("Save & test") { Task { await saveAndTest() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(busy)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .textFieldStyle(.roundedBorder)
        .onAppear { specs = CamsConfig.load() }
    }

    private func camCard(_ spec: Binding<CamSpec>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                TextField("Name shown on the frame", text: spec.name)
                Text("Refresh").font(.caption).foregroundStyle(.secondary)
                TextField("5", value: spec.refreshMinutes,
                          format: .number.grouping(.never))
                    .frame(width: 44)
                Text("min").font(.caption).foregroundStyle(.secondary)
                Button(role: .destructive) {
                    let id = spec.id.wrappedValue
                    specs.removeAll { $0.id == id }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(specs.count == 1)
            }
            TextField("Image URL (https://…/latest.jpg)", text: spec.imageURL)
                .font(.system(.caption, design: .monospaced))
            TextField("Page URL opened on click", text: spec.pageURL)
                .font(.system(.caption, design: .monospaced))
        }
        .padding(8)
        .background(Color.primary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 8))
    }

    /// Save, then HEAD-check each configured image URL so a typo shows up here
    /// rather than as an empty widget.
    private func saveAndTest() async {
        busy = true
        defer { busy = false }
        status = nil

        guard CamsConfig.save(specs) else {
            status = "Could not write the config file."
            statusColor = .red
            return
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "Webcam")

        var ok: [String] = []
        var bad: [String] = []
        for spec in specs where spec.isConfigured {
            if await reachable(spec) { ok.append(spec.name) } else { bad.append(spec.name) }
        }

        if ok.isEmpty && bad.isEmpty {
            status = "Saved ✓ — no image URLs set yet."
            statusColor = .orange
        } else if bad.isEmpty {
            status = "Saved ✓ — reached \(ok.joined(separator: ", "))."
            statusColor = .green
        } else {
            status = "Saved, but couldn’t load: \(bad.joined(separator: ", "))."
            statusColor = .orange
        }
    }

    private func reachable(_ spec: CamSpec) async -> Bool {
        guard let url = spec.image else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        req.timeoutInterval = 10
        guard let (_, resp) = try? await URLSession.shared.data(for: req) else { return false }
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }
}
