import SwiftUI
import WidgetKit

/// Add, edit and remove tide locations. Stored in the shared App Group
/// container so the tide widgets and watch complication read the same values.
///
/// The tide itself is synthesized locally from windguru's harmonic
/// constituents (fetched once per spot); maree.info is only the page a widget
/// click opens. Each location carries any number of thresholds — one dashed
/// line per value on the charts, one chord on the watch dial.
struct TideSettingsView: View {
    @State private var locations: [TideLocation] = TideConfig.load()
    @State private var status: String?
    @State private var statusColor: Color = .secondary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Tide").font(.headline)
                Text("Curve, high/low times and the French coefficient, computed on-device from the bundled harmonic port catalog — no network at all. “maree.info id” only sets the page a click opens. Thresholds draw one line each; the first is the primary one on the compact faces.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ConfigEntryList(
                    items: $locations,
                    addLabel: "Add location",
                    newItem: {
                        TideLocation(id: UUID().uuidString, title: "New location",
                                     port: "PORNIC, France",
                                     mareeInfoId: 119, thresholds: [3.5])
                    },
                    header: { loc in
                        TextField("Name shown as the widget heading", text: loc.title)
                    },
                    detail: { loc in
                        locationFields(loc)
                    })

                HStack(spacing: 8) {
                    if let status {
                        Text(status).font(.caption).foregroundStyle(statusColor)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("Save") { save() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(locations.isEmpty)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .textFieldStyle(.roundedBorder)
        .onAppear { locations = TideConfig.load() }
    }

    private func locationFields(_ loc: Binding<TideLocation>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TidePortPicker(selection: loc.port)
            LabeledField(title: "maree.info id") {
                TextField("119", value: loc.mareeInfoId, format: .number.grouping(.never))
            }
            HStack(spacing: 8) {
                LabeledField(title: "Calibration") {
                    TextField("scale", value: loc.heightScale, format: .number)
                        .frame(width: 64)
                }
                TextField("bias m", value: loc.heightBias, format: .number)
                    .frame(width: 64)
            }
            Text("Optional height correction h' = scale·h + bias, fitted against maree.info's table for the port. Leave empty for the raw harmonic prediction.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LabeledField(title: "Thresholds (m)") {
                HStack(spacing: 6) {
                    ForEach(loc.thresholds.indices, id: \.self) { i in
                        TextField("3.8", value: loc.thresholds[i], format: .number)
                            .frame(width: 54)
                        Button {
                            loc.wrappedValue.thresholds.remove(at: i)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .disabled(loc.wrappedValue.thresholds.count <= 1)
                    }
                    Button {
                        loc.wrappedValue.thresholds.append(
                            (loc.wrappedValue.thresholds.last ?? 3.5) + 0.3)
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            Toggle("Show as a page in the watch app",
                   isOn: Binding(get: { loc.wrappedValue.onWatch },
                                 set: { loc.wrappedValue.watch = $0 }))
                .font(.caption)
        }
    }

    private func save() {
        guard TideConfig.save(locations) else {
            status = "Could not write tide.json"
            statusColor = .red
            return
        }
        status = "Saved."
        statusColor = .secondary
        WidgetCenter.shared.reloadTimelines(ofKind: "TideToday")
        WidgetCenter.shared.reloadTimelines(ofKind: "TideDays")
    }
}

/// Search-and-pick a port from the bundled harmonic catalog (~1500 ports).
/// Results sort by distance to the currently selected port when one is set,
/// so nearby alternatives surface first; otherwise by name match.
struct TidePortPicker: View {
    @Binding var selection: String?
    @State private var query = ""
    @State private var searching = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledField(title: "Port") {
                HStack(spacing: 6) {
                    Text(selection ?? "none — pick one")
                        .font(.caption)
                        .foregroundStyle(selection == nil ? .secondary : .primary)
                        .lineLimit(1)
                    Button(searching ? "Done" : "Change") { searching.toggle() }
                        .font(.caption)
                }
            }
            if searching {
                TextField("Search port (e.g. Pornic)", text: $query)
                let near = TidePorts.port(selection).flatMap { p in
                    p.lon.flatMap { lon in p.lat.map { (lon: lon, lat: $0) } }
                }
                ForEach(TidePorts.names(matching: query, near: near).prefix(8), id: \.self) { name in
                    Button {
                        selection = name
                        searching = false
                        query = ""
                    } label: {
                        HStack {
                            Text(name).font(.caption).lineLimit(1)
                            Spacer()
                            if name == selection { Image(systemName: "checkmark") }
                        }
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }
}
