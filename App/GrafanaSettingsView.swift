import SwiftUI
import WidgetKit

/// Add, edit and remove Grafana sources. Each source is a connection plus one
/// editable slot per thing drawn: the layout skeleton is fixed (rose + big value
/// + secondary line, then rows of three chips) and a slot's role says where it
/// lands.
///
/// A placed Live Metrics widget remembers which source it shows in its own
/// configuration intent (right-click → Edit Widget). Tokens are stored in the
/// shared App Group container, never in source.
struct GrafanaSettingsView: View {
    @State private var sources: [GrafanaSource] = GrafanaConfig.load()
    @State private var status: String?
    @State private var statusColor: Color = .secondary
    @State private var busy = false
    /// Last test's values, per source, so each slot can preview what it renders.
    @State private var probes: [String: WindSnapshot] = [:]
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var compact: Bool { sizeClass == .compact }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Grafana live metrics").font(.headline)
                Text("Each slot is one raw InfluxQL query sent to Grafana’s /api/ds/query. The role decides where it is drawn; the scale decides how it is coloured. Chips fill rows of three in the order listed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ConfigEntryList(
                    items: $sources,
                    addLabel: "Add source",
                    newItem: { GrafanaSource(title: "New source") },
                    duplicate: duplicate,
                    header: { source in
                        TextField("Name shown as the widget heading", text: source.title)
                    },
                    detail: { source in
                        VStack(alignment: .leading, spacing: 10) {
                            connectionFields(source)
                            Divider()
                            slotsSection(source)
                        }
                    })

                HStack(spacing: 8) {
                    if busy { ProgressView().controlSize(.small) }
                    if let status {
                        Text(status).font(.caption).foregroundStyle(statusColor)
                            .lineLimit(4).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("Save & test") { Task { await saveAndTest() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled(busy || sources.isEmpty)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .textFieldStyle(.roundedBorder)
        .onAppear { sources = GrafanaConfig.load() }
    }

    /// Copy a source with fresh ids — the quick path to a second station with the
    /// same slot shapes but a different host or measurement names.
    private func duplicate(_ i: Int) {
        var copy = sources[i]
        copy.id = UUID().uuidString
        copy.title += " copy"
        copy.slots = copy.slots.map { slot in
            var s = slot
            s.id = UUID().uuidString
            return s
        }
        sources.insert(copy, at: i + 1)
    }

    // MARK: Connection

    private func connectionFields(_ source: Binding<GrafanaSource>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledField(title: "Grafana") {
                TextField("https://host/grafana", text: source.baseURL)
                    .font(.system(.caption, design: .monospaced))
            }
            LabeledField(title: "Token") {
                HStack(spacing: 6) {
                    SecureField("glsa_… (service-account token)", text: source.token)
                        .font(.system(.caption, design: .monospaced))
                    if source.token.wrappedValue.isEmpty {
                        Text("required").font(.caption2).foregroundStyle(.orange)
                    }
                }
            }
            LabeledField(title: "Data source") {
                HStack(spacing: 12) {
                    TextField("1", value: source.datasourceId,
                              format: .number.grouping(.never))
                        .settingsWidth(50)
                    Text("Window").font(.caption).foregroundStyle(.secondary)
                    TextField("now-3h", text: source.window)
                        .settingsWidth(90)
                        .font(.system(.caption, design: .monospaced))
                    Spacer(minLength: 0)
                }
            }
            LabeledField(title: "Dashboard") {
                TextField("URL opened when the widget is clicked",
                          text: source.dashboardURL)
                    .font(.system(.caption, design: .monospaced))
            }
        }
    }

    // MARK: Slots

    private func slotsSection(_ source: Binding<GrafanaSource>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Slots").font(.system(size: 12, weight: .semibold))
                Spacer()
                Button {
                    source.slots.wrappedValue.append(
                        MetricSlot(role: .chip, query: "SELECT last(value) FROM autogen."))
                } label: {
                    Label("Add chip", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }

            ForEach(source.slots) { $slot in
                slotCard($slot, in: source)
            }

            Text("Roles other than Chip fill a single place in the layout — if two slots share one, the first enabled slot wins. “Dew spread” colours by how close the value is to the Temperature-scaled slot.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func slotCard(_ slot: Binding<MetricSlot>,
                          in source: Binding<GrafanaSource>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if compact {
                HStack(spacing: 6) {
                    enableToggle(slot)
                    rolePicker(slot)
                    Spacer(minLength: 0)
                    deleteButton(slot, in: source)
                }
                HStack(spacing: 6) {
                    TextField("Label", text: slot.label)
                    TextField("Unit", text: slot.unit).settingsWidth(64)
                    decimalStepper(slot)
                }
            } else {
                HStack(spacing: 6) {
                    enableToggle(slot)
                    rolePicker(slot)
                    TextField("Label", text: slot.label).settingsWidth(74)
                    TextField("Unit", text: slot.unit).settingsWidth(54)
                    decimalStepper(slot)
                    Spacer(minLength: 0)
                    deleteButton(slot, in: source)
                }
            }

            HStack(spacing: 6) {
                Picker("", selection: slot.scale) {
                    ForEach(MetricScale.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .settingsWidth(150)
                .disabled(slot.role.wrappedValue == .series)
                preview(slot.wrappedValue, in: source.wrappedValue)
                Spacer(minLength: 0)
            }

            TextField("SELECT last(value) FROM autogen.measurement", text: slot.query,
                      axis: .vertical)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1...3)

            if slot.role.wrappedValue != .series {
                TextField("Trend query — optional, adds a tendency arrow",
                          text: slot.trendQuery)
                    .font(.system(.caption, design: .monospaced))
            }
        }
        .padding(8)
        .background(Color.primary.opacity(slot.enabled.wrappedValue ? 0.05 : 0.02),
                    in: RoundedRectangle(cornerRadius: 6))
        .opacity(slot.enabled.wrappedValue ? 1 : 0.55)
    }

    private func enableToggle(_ slot: Binding<MetricSlot>) -> some View {
        Toggle("", isOn: slot.enabled)
            .labelsHidden()
            .help("Include this metric")
    }

    private func rolePicker(_ slot: Binding<MetricSlot>) -> some View {
        Picker("", selection: slot.role) {
            ForEach(SlotRole.allCases) { Text($0.label).tag($0) }
        }
        .labelsHidden()
        // Capped on a Mac so the row stays aligned; uncapped on a phone, where
        // 122pt clips the longer role names ("Big number", "Rose (degrees)").
        .settingsWidth(compact ? .infinity : 122)
    }

    private func decimalStepper(_ slot: Binding<MetricSlot>) -> some View {
        Stepper(value: slot.decimals, in: 0...3) {
            Text("\(slot.decimals.wrappedValue)dp")
                .font(.caption).foregroundStyle(.secondary)
        }
        .fixedSize()
    }

    private func deleteButton(_ slot: Binding<MetricSlot>,
                              in source: Binding<GrafanaSource>) -> some View {
        Button(role: .destructive) {
            let id = slot.id.wrappedValue
            source.slots.wrappedValue.removeAll { $0.id == id }
        } label: {
            Image(systemName: "trash")
        }
        .buttonStyle(.borderless)
        .disabled(source.slots.wrappedValue.count == 1)
    }

    /// What the widget would print for this slot, using the last test's values.
    @ViewBuilder
    private func preview(_ slot: MetricSlot, in source: GrafanaSource) -> some View {
        let probe = probes[source.id]
        if slot.role == .series {
            Text(probe.map { "\($0.series.count) points" } ?? "sparkline")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            let v = probe?.values[slot.id]
            let ref = probe.flatMap { p in
                source.slots.first { $0.scale == .temperature }.flatMap { p.values[$0.id] }
            }
            Text(slot.text(v, trend: probe?.trends[slot.id]))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(slot.scale.color(v, reference: ref))
        }
    }

    // MARK: Save & test

    private func saveAndTest() async {
        busy = true
        defer { busy = false }
        status = nil

        guard GrafanaConfig.save(sources) else {
            status = "Could not write the config file."
            statusColor = .red
            return
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "LiveMetrics")

        var lines: [String] = []
        var worst = Color.green
        for source in sources {
            guard source.isConfigured else {
                lines.append("“\(source.title)”: needs a URL and token")
                worst = .orange
                continue
            }
            guard let snap = await Grafana.fetchAll(source) else {
                lines.append("“\(source.title)”: nothing came back — check URL, token, data source id")
                worst = .orange
                continue
            }
            probes[source.id] = snap
            let wanted = source.slots.filter { $0.enabled && !$0.query.isEmpty }
            let missing = wanted.filter { s in
                s.role == .series ? snap.series.isEmpty : snap.values[s.id] == nil
            }
            if missing.isEmpty {
                lines.append("“\(source.title)”: all \(wanted.count) slots ✓")
            } else {
                let names = missing.map { $0.label.isEmpty ? $0.role.label : $0.label }
                lines.append("“\(source.title)”: no data for \(names.joined(separator: ", "))")
                worst = .orange
            }
        }
        status = "Saved. " + lines.joined(separator: " · ")
        statusColor = worst
    }
}
