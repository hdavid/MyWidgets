import SwiftUI
import WidgetKit
import UniformTypeIdentifiers

/// A JSON config export. `FileDocument` rather than a save panel so the same
/// code drives the macOS file dialog and the iOS document picker / share sheet.
struct ConfigDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Export the whole setup to a file and import it back — the way to move a
/// configuration to another Mac, or to the iPhone app.
struct ConfigSettingsView: View {
    @State private var includeTokens = false
    @State private var exporting = false
    @State private var importing = false
    @State private var document = ConfigDocument(data: Data())
    @State private var status: String?
    @State private var statusColor: Color = .secondary

    private var current: ConfigBundle { ConfigBundle.current(includeTokens: includeTokens) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Import / export").font(.headline)
                Text("One JSON file holding every Grafana source, windguru spot, webcam and Claude account. Use it to move a setup to another machine, or to the iPhone app — which reads the same format.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(current.summary)
                            .font(.system(size: 12, weight: .semibold))

                        Toggle("Include Grafana tokens", isOn: $includeTokens)
                            .font(.callout)
                        Text(includeTokens
                             ? "The file will contain \(current.tokenCount) bearer token\(current.tokenCount == 1 ? "" : "s") in plain text. Treat it like a password."
                             : "Tokens are left out. Importing keeps whatever tokens the target machine already has, so a token-less file won't wipe them.")
                            .font(.caption2)
                            .foregroundStyle(includeTokens ? .orange : .secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack {
                            Button {
                                export()
                            } label: {
                                Label("Export…", systemImage: "square.and.arrow.up")
                            }
                            Button {
                                importing = true
                            } label: {
                                Label("Import…", systemImage: "square.and.arrow.down")
                            }
                            Spacer()
                        }
                    }
                    .padding(4)
                }

                Button {
                    WidgetCenter.shared.reloadAllTimelines()
                    status = "Asked every widget to reload."
                    statusColor = .secondary
                } label: {
                    Label("Reload all widgets", systemImage: "arrow.clockwise")
                }

                if let status {
                    Text(status).font(.caption).foregroundStyle(statusColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fileExporter(isPresented: $exporting, document: document,
                      contentType: .json,
                      defaultFilename: "MyWidgets-config") { result in
            switch result {
            case .success:
                status = "Exported ✓ — \(current.summary)."
                statusColor = .green
            case .failure(let error):
                status = "Export failed: \(error.localizedDescription)"
                statusColor = .red
            }
        }
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): importFile(url)
            case .failure(let error):
                status = "Import failed: \(error.localizedDescription)"
                statusColor = .red
            }
        }
    }

    private func export() {
        do {
            document = ConfigDocument(data: try current.encoded())
            exporting = true
        } catch {
            status = "Could not build the export: \(error.localizedDescription)"
            statusColor = .red
        }
    }

    private func importFile(_ url: URL) {
        // The picker hands back a URL outside the sandbox; it has to be opened
        // through a security scope before it can be read.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        do {
            let bundle = try ConfigBundle.decoded(try Data(contentsOf: url))
            guard bundle.apply() else {
                status = "Read the file, but could not write the config."
                statusColor = .red
                return
            }
            WidgetCenter.shared.reloadAllTimelines()
            status = "Imported ✓ — \(bundle.summary). Reopen the other tabs to see them."
            statusColor = .green
        } catch {
            status = "Import failed: \(error.localizedDescription)"
            statusColor = .red
        }
    }
}
