import SwiftUI
import WidgetKit

/// Add, edit and remove windguru spots. Stored in the shared App Group container
/// so the widget reads the same values. No login is needed — every single model
/// is public; only windguru's browser-side "WG" blend isn't a fetchable dataset,
/// so it isn't offered here.
///
/// A placed forecast widget remembers which spot it shows in its own
/// configuration intent (right-click → Edit Widget).
struct WindguruSettingsView: View {
    @State private var spots: [WindguruSpot] = WindguruConfig.load()
    /// Per spot, since which models exist depends on the region.
    @State private var models: [String: [WindguruModel]] = [:]
    @State private var status: String?
    @State private var statusColor: Color = .secondary
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Windguru forecast").font(.headline)
                Text("Wind, gust, direction and temperature (knots), daylight hours only. Find a spot's id in its windguru.cz URL. “Load models” asks that spot which models it offers — resolution varies by region. The blended “WG” isn't available: windguru computes it in the browser, so there's no dataset to fetch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ConfigEntryList(
                    items: $spots,
                    addLabel: "Add spot",
                    newItem: { WindguruSpot(title: "New spot") },
                    header: { spot in
                        TextField("Name shown as the widget heading", text: spot.title)
                    },
                    detail: { spot in
                        spotFields(spot)
                    })

                HStack(spacing: 8) {
                    if busy { ProgressView().controlSize(.small) }
                    if let status {
                        Text(status).font(.caption).foregroundStyle(statusColor)
                            .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("Save & test") { Task { await saveAndTest() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(busy || spots.isEmpty)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .textFieldStyle(.roundedBorder)
        .onAppear { spots = WindguruConfig.load() }
    }

    private func spotFields(_ spot: Binding<WindguruSpot>) -> some View {
        let id = spot.id.wrappedValue
        let configured = spot.spotId.wrappedValue > 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Spot ID").font(.caption).foregroundStyle(.secondary)
                TextField("e.g. 67620", value: spot.spotId,
                          format: .number.grouping(.never))
                    .settingsWidth(90)
                if configured {
                    Link("open", destination: Windguru.pageURL(spot: spot.spotId.wrappedValue))
                        .font(.caption)
                } else {
                    Text("required").font(.caption2).foregroundStyle(.orange)
                }
                Spacer()
                Button("Load models") {
                    Task { await loadModels(for: spot.wrappedValue) }
                }
                .disabled(busy || !configured)
            }
            HStack {
                Text("Model").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: spot.idModel) {
                    ForEach(models[id] ?? WindguruCatalog.windModels(available: nil)) { m in
                        Text(m.name).tag(m.id)
                    }
                }
                .labelsHidden()
                .settingsWidth(220)
                Spacer()
            }
        }
    }

    /// Ask the spot which models it offers and rebuild its picker (highest
    /// resolution first).
    private func loadModels(for spot: WindguruSpot) async {
        guard spot.isConfigured else { return }
        busy = true
        defer { busy = false }
        let ids = await Windguru.spotModels(spot: spot.spotId)
        let available = WindguruCatalog.windModels(available: ids)
        models[spot.id] = available
        if let i = spots.firstIndex(where: { $0.id == spot.id }),
           !available.contains(where: { $0.id == spots[i].idModel }),
           let first = available.first {
            spots[i].idModel = first.id
        }
    }

    private func saveAndTest() async {
        busy = true
        defer { busy = false }
        status = nil

        guard WindguruConfig.save(spots) else {
            status = "Could not write the config file."
            statusColor = .red
            return
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "WindguruForecast")

        let unset = spots.filter { !$0.isConfigured }
        var ok: [String] = []
        var bad: [String] = []
        for spot in spots where spot.isConfigured {
            if await Windguru.fetch(spot) != nil { ok.append(spot.heading) }
            else { bad.append(spot.heading) }
        }

        if !bad.isEmpty {
            status = "Saved, but no forecast for: \(bad.joined(separator: ", ")) — check the spot ids."
            statusColor = .orange
        } else if !unset.isEmpty {
            status = "Saved ✓ — \(unset.count) spot\(unset.count == 1 ? "" : "s") still need a spot id."
            statusColor = .orange
        } else {
            status = "Saved ✓ — \(ok.joined(separator: ", "))."
            statusColor = .green
        }
    }
}
