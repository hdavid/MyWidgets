import SwiftUI
import WidgetKit

/// Configure the Windguru forecast widget: spot and model. Settings live in the
/// shared App Group container so the widget reads the same values. No login is
/// needed — every single model is public; only windguru's browser-side "WG"
/// blend isn't a fetchable dataset, so it isn't offered here.
struct WindguruSettingsView: View {
    @State private var settings = WindguruConfig.load()
    @State private var models = WindguruCatalog.windModels(available: nil)
    @State private var status: String?
    @State private var statusColor: Color = .secondary
    @State private var busy = false

    private var selectedModel: WindguruModel? { WindguruCatalog.model(settings.idModel) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Windguru forecast").font(.headline)
            Text("Wind, gust and direction (knots), daylight hours only. AROME-FR 1.3 km is the highest-resolution model for this coast. The blended “WG” isn’t available — windguru computes it in the browser, so there’s no dataset to fetch.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("Spot ID").frame(width: 64, alignment: .leading)
                TextField("67620", value: $settings.spotId,
                          format: .number.grouping(.never))
                    .frame(width: 90)
                Link("open", destination: Windguru.pageURL(spot: settings.spotId))
                    .font(.caption)
                Spacer()
                Button("Load models") { Task { await loadModels() } }
                    .disabled(busy)
            }

            HStack {
                Text("Model").frame(width: 64, alignment: .leading)
                Picker("", selection: $settings.idModel) {
                    ForEach(models) { m in Text(m.name).tag(m.id) }
                }
                .labelsHidden()
                .frame(width: 220)
                Spacer()
            }

            HStack(spacing: 8) {
                if busy { ProgressView().controlSize(.small) }
                if let status {
                    Text(status).font(.caption).foregroundStyle(statusColor)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Save & test") { Task { await saveAndTest() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(busy)
            }
        }
        .padding(14)
        .textFieldStyle(.roundedBorder)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            settings = WindguruConfig.load()
            Task { await loadModels() }
        }
    }

    /// Ask the spot which models it offers and rebuild the picker (hi-res first).
    private func loadModels() async {
        busy = true
        defer { busy = false }
        let ids = await Windguru.spotModels(spot: settings.spotId)
        models = WindguruCatalog.windModels(available: ids)
        if !models.contains(where: { $0.id == settings.idModel }),
           let first = models.first {
            settings.idModel = first.id
        }
    }

    private func saveAndTest() async {
        busy = true
        defer { busy = false }
        status = nil

        WindguruConfig.save(settings)
        guard let f = await Windguru.fetch(settings) else {
            status = "Saved, but no forecast came back — try again."
            statusColor = .orange
            return
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "MoutiersForecast")

        let requested = selectedModel?.name ?? ""
        if !requested.isEmpty, f.model != requested {
            status = "Saved ✓ — showing \(f.model) (couldn’t reach \(requested))."
        } else {
            status = "Saved ✓ — \(f.model)."
        }
        statusColor = .green
    }
}
