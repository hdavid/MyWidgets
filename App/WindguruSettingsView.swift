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
    @State private var stations: [WindguruStation] = WindguruStationsConfig.load()
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

                Text("Live stations").font(.headline).padding(.top, 8)
                Text("Live wind from a windguru weather station — the Windguru Station widget shows it like the Grafana one. A station's id is the number in its page URL: windguru.cz/station/2323 → 2323. Leave the name empty and “Save & test” fills it with the station's own.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Link("Find a station on the windguru stations map",
                     destination: Windguru.stationsMapURL)
                    .font(.caption)

                ConfigEntryList(
                    items: $stations,
                    addLabel: "Add station",
                    newItem: { WindguruStation() },
                    header: { station in
                        TextField("Name shown as the widget heading", text: station.title)
                    },
                    detail: { station in
                        stationFields(station)
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
                        .disabled(busy || (spots.isEmpty && stations.isEmpty))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .textFieldStyle(.roundedBorder)
        .onAppear {
            spots = WindguruConfig.load()
            stations = WindguruStationsConfig.load()
        }
    }

    private func spotFields(_ spot: Binding<WindguruSpot>) -> some View {
        let id = spot.id.wrappedValue
        let configured = spot.spotId.wrappedValue > 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Spot ID").font(.caption).foregroundStyle(.secondary)
                TextField("from the windguru.cz URL", value: spot.spotId,
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
            tideFields(spot)
            // The watch pairs with an iPhone only — hide everywhere else.
            #if os(iOS)
            if UIDevice.current.userInterfaceIdiom == .phone {
                Toggle("Show as a page in the watch app",
                       isOn: Binding(get: { spot.wrappedValue.onWatch },
                                     set: { spot.wrappedValue.watch = $0 }))
                    .font(.caption)
            }
            #endif
        }
    }

    private func stationFields(_ station: Binding<WindguruStation>) -> some View {
        let configured = station.stationId.wrappedValue > 0
        return HStack {
            Text("Station ID").font(.caption).foregroundStyle(.secondary)
            TextField("from the station page URL", value: station.stationId,
                      format: .number.grouping(.never))
                .settingsWidth(90)
            if configured {
                Link("open", destination: Windguru.stationPageURL(station: station.stationId.wrappedValue))
                    .font(.caption)
            } else {
                Text("required").font(.caption2).foregroundStyle(.orange)
            }
            Spacer()
        }
    }

    /// Optional, and only meaningful on a coastal spot: what the tide row needs
    /// to speak in the same numbers as a printed tide table. Deliberately
    /// separate from the Tide tab — the forecast row uses windguru's own
    /// constituents, the tide widgets use the port catalog.
    private func tideFields(_ spot: Binding<WindguruSpot>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Tide table offset").font(.caption).foregroundStyle(.secondary)
                TextField("m", value: spot.tideOffset, format: .number.precision(.fractionLength(0...2)))
                    .settingsWidth(70)
                Text("m").font(.caption2).foregroundStyle(.secondary)
                Text("Green above").font(.caption).foregroundStyle(.secondary)
                TextField("m", value: spot.tideGreenAbove,
                          format: .number.precision(.fractionLength(0...2)))
                    .settingsWidth(70)
                Text("m").font(.caption2).foregroundStyle(.secondary)
                Spacer()
            }
            Text(tideHelp(spot.wrappedValue))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Says what the two numbers currently mean, so the calibration can be
    /// checked without leaving the tab.
    private func tideHelp(_ spot: WindguruSpot) -> String {
        let base = "Windguru's tide is metres from mean sea level; tide tables use a local zero. At any high or low water, subtract windguru's height from your table's to get the offset. Leave both empty for a plain blue tide row."
        guard let msl = spot.greenAboveMSL else { return base }
        return base + String(format: " Now: green above %+.2f m from mean sea level.", msl / 100)
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

        guard WindguruConfig.save(spots), WindguruStationsConfig.save(stations) else {
            status = "Could not write the config file."
            statusColor = .red
            return
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "WindguruForecast")
        WidgetCenter.shared.reloadTimelines(ofKind: "WindguruStation")

        let unset = spots.filter { !$0.isConfigured }.count
                  + stations.filter { !$0.isConfigured }.count
        var ok: [String] = []
        var bad: [String] = []
        for spot in spots where spot.isConfigured {
            if await Windguru.fetch(spot) != nil { ok.append(spot.heading) }
            else { bad.append(spot.heading) }
        }
        for i in stations.indices where stations[i].isConfigured {
            if await Windguru.stationCurrent(station: stations[i].stationId) != nil {
                // An empty name gets the station's own, so the widget picker,
                // the heading and the status line below say something better
                // than "Station 2323".
                if stations[i].title.isEmpty,
                   let name = await Windguru.stationName(station: stations[i].stationId) {
                    stations[i].title = name
                    WindguruStationsConfig.save(stations)
                }
                ok.append(stations[i].heading)
            } else {
                bad.append(stations[i].heading)
            }
        }

        if !bad.isEmpty {
            status = "Saved, but nothing came back for: \(bad.joined(separator: ", ")) — check the ids."
            statusColor = .orange
        } else if unset > 0 {
            status = "Saved ✓ — \(unset) entr\(unset == 1 ? "y" : "ies") still need an id."
            statusColor = .orange
        } else {
            status = "Saved ✓ — \(ok.joined(separator: ", "))."
            statusColor = .green
        }
    }
}
