// macOS only — Claude usage can't be read on iOS, so there's nothing to configure.
#if os(macOS)
import SwiftUI
import WidgetKit

/// Edit the Claude accounts the usage widget tracks. Stored in the shared App
/// Group container so the widget's self-fetcher sees the same list.
struct AccountSettingsView: View {
    @ObservedObject var model: UsageAppModel
    @State private var specs: [AccountSpec] = AccountsConfig.load()
    @State private var saved = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Claude accounts").font(.headline)
                Text("Each account is read from a Claude Code Keychain item. The default login uses “Claude Code-credentials”; extra accounts (CLAUDE_CONFIG_DIR setups) use a suffixed item name.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ConfigEntryList(
                    items: $specs,
                    addLabel: "Add account",
                    newItem: {
                        AccountSpec(label: "New account", cli: "claude",
                                    keychainService: "Claude Code-credentials")
                    },
                    header: { spec in
                        TextField("Label", text: spec.label)
                    },
                    detail: { spec in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text("CLI").font(.caption).foregroundStyle(.secondary)
                                TextField("claude", text: spec.cli)
                                    .frame(width: 110)
                                Spacer()
                            }
                            TextField("Keychain service (e.g. Claude Code-credentials)",
                                      text: spec.keychainService)
                                .font(.system(.caption, design: .monospaced))
                        }
                    })

                HStack {
                    if saved {
                        Text("Saved ✓").font(.caption).foregroundStyle(.green)
                    }
                    Spacer()
                    Button("Save & refresh") {
                        AccountsConfig.save(specs)
                        saved = true
                        model.refresh(force: true)
                        WidgetCenter.shared.reloadTimelines(ofKind: "ClaudeUsageWidget")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .textFieldStyle(.roundedBorder)
        .onAppear { specs = AccountsConfig.load() }
    }
}

#endif
