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
    /// Slot ids with their options row unfolded.
    @State private var expandedSlots: Set<String> = []
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
                            // The watch pairs with an iPhone only — hide everywhere else.
                            #if os(iOS)
                            if UIDevice.current.userInterfaceIdiom == .phone {
                                Toggle("Show as a page in the watch app",
                                       isOn: Binding(get: { source.wrappedValue.onWatch },
                                                     set: { source.wrappedValue.watch = $0 }))
                                    .font(.caption)
                            }
                            #endif
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

    /// The layout is fixed, so the editor is a fixed checklist: one query
    /// line per place in the widget, options folded behind the chevron.
    /// Empty query = that place stays empty.
    private func slotsSection(_ source: Binding<GrafanaSource>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Queries").font(.system(size: 12, weight: .semibold))
            ForEach(fixedRows(source), id: \.title) { row in
                slotRow(row.title, row.slot, in: source)
            }
            Text("Raw InfluxQL per place. “Dew spread” colours by how close the value is to the Temperature-scaled chip.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { canonicalize(source) }
    }

    private struct FixedRow {
        let title: String
        let slot: Binding<MetricSlot>
    }

    /// Slots are kept in canonical order (big number, under it, rose,
    /// sparkline, then six chips), so rows bind by index.
    private func fixedRows(_ source: Binding<GrafanaSource>) -> [FixedRow] {
        guard source.slots.wrappedValue.count >= 10 else { return [] }
        let titles = ["Big number", "Under it", "Rose °", "Sparkline",
                      "Chip 1", "Chip 2", "Chip 3", "Chip 4", "Chip 5", "Chip 6"]
        return titles.indices.map { FixedRow(title: titles[$0], slot: source.slots[$0]) }
    }

    /// Rebuild the slots array into canonical order, creating empty slots for
    /// unfilled places and keeping anything unrecognized at the tail so an
    /// older config never loses data it can't display.
    private func canonicalize(_ source: Binding<GrafanaSource>) {
        var pool = source.slots.wrappedValue
        guard !(pool.count >= 10 && pool[0].role == .primary && pool[1].role == .secondary
                && pool[2].role == .direction && pool[3].role == .series) else { return }
        func take(_ role: SlotRole) -> MetricSlot {
            if let i = pool.firstIndex(where: { $0.role == role }) {
                return pool.remove(at: i)
            }
            return MetricSlot(role: role, query: "")
        }
        var out = [take(.primary), take(.secondary), take(.direction), take(.series)]
        for _ in 0..<6 { out.append(take(.chip)) }
        out += pool   // e.g. an old tertiary slot — preserved, not shown
        source.slots.wrappedValue = out
    }

    private func slotRow(_ title: String, _ slot: Binding<MetricSlot>,
                         in source: Binding<GrafanaSource>) -> some View {
        let open = expandedSlots.contains(slot.id.wrappedValue)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(width: 74, alignment: .leading)
                TextField("empty — not shown", text: slot.query, axis: .vertical)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1...3)
                if !slot.query.wrappedValue.isEmpty {
                    preview(slot.wrappedValue, in: source.wrappedValue)
                }
                Button {
                    if open { expandedSlots.remove(slot.id.wrappedValue) }
                    else { expandedSlots.insert(slot.id.wrappedValue) }
                } label: {
                    Image(systemName: open ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
            }
            if open {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        TextField("Label", text: slot.label).settingsWidth(74)
                        TextField("Unit", text: slot.unit).settingsWidth(54)
                        Stepper(value: slot.decimals, in: 0...3) {
                            Text("\(slot.decimals.wrappedValue)dp")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .fixedSize()
                        if slot.role.wrappedValue != .series {
                            Picker("", selection: slot.scale) {
                                ForEach(MetricScale.allCases) { Text($0.label).tag($0) }
                            }
                            .labelsHidden()
                            .settingsWidth(150)
                        }
                        Spacer(minLength: 0)
                    }
                    if slot.role.wrappedValue != .series {
                        TextField("Trend query — optional, adds a tendency arrow",
                                  text: slot.trendQuery)
                            .font(.system(.caption, design: .monospaced))
                    }
                }
                .padding(.leading, 80)
            }
        }
    }

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

        var trimmed = sources
        for i in trimmed.indices {
            trimmed[i].slots.removeAll { $0.query.isEmpty }
            for j in trimmed[i].slots.indices { trimmed[i].slots[j].enabled = true }
        }
        guard GrafanaConfig.save(trimmed) else {
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
