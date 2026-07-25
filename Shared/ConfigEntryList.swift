import SwiftUI

/// The one add/remove list every config tab uses, so Grafana sources, windguru
/// spots, webcams and Claude accounts all behave the same way.
///
/// Each entry is a card: a header that stays visible (its name, plus optional
/// actions) and a disclosure holding the details. The disclosure is what makes a
/// single pattern work for both a webcam — three fields — and a Grafana source,
/// which carries a connection plus a dozen metric slots.
struct ConfigEntryList<Item: Identifiable, Header: View, Detail: View>: View {
    @Binding var items: [Item]
    /// Text for the button that appends an entry, e.g. "Add webcam".
    var addLabel: String
    /// Builds the entry to append.
    var newItem: () -> Item
    /// Smallest list the tab can work with — the delete buttons disable here.
    var minimum: Int = 1
    /// Optional per-entry copy action; the button only appears when set.
    var duplicate: ((Int) -> Void)?
    @ViewBuilder var header: (Binding<Item>) -> Header
    @ViewBuilder var detail: (Binding<Item>) -> Detail

    /// Collapsed by default once there's more than one entry: with several
    /// sources open at once the tab turns into an unreadable wall of queries.
    @State private var expanded: Set<Item.ID> = []
    @State private var primed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items.indices, id: \.self) { i in
                if i < items.count { card(i) }
            }

            Button {
                let item = newItem()
                items.append(item)
                expanded.insert(item.id)   // a new entry needs filling in
            } label: {
                Label(addLabel, systemImage: "plus")
            }
        }
        .onAppear {
            guard !primed else { return }
            primed = true
            if items.count == 1, let only = items.first { expanded.insert(only.id) }
        }
    }

    private func card(_ i: Int) -> some View {
        let id = items[i].id
        let isOpen = expanded.contains(id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button {
                    if isOpen { expanded.remove(id) } else { expanded.insert(id) }
                } label: {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                }
                .buttonStyle(.borderless)
                .help(isOpen ? "Collapse" : "Expand")

                header($items[i])

                if let duplicate {
                    Button { duplicate(i) } label: {
                        Image(systemName: "plus.square.on.square")
                    }
                    .buttonStyle(.borderless)
                    .help("Duplicate")
                }

                Button(role: .destructive) {
                    expanded.remove(id)
                    items.remove(at: i)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(items.count <= minimum)
                .help("Remove")
            }

            if isOpen {
                detail($items[i])
                    .padding(.leading, 20)
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 8))
    }
}
