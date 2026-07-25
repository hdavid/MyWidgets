import AppIntents
import WidgetKit

// Per-instance widget configuration. This is what makes "add / remove" work at
// all: WidgetKit only knows the widget *kinds* compiled into the extension, so
// there is one Webcam widget and one Live Metrics widget, and each placed copy
// stores which configured entry it shows. Right-click a widget → Edit Widget to
// change the selection.
//
// The pickers list whatever is in the App Group config, so adding a webcam in
// the app immediately offers it here.

// MARK: - Webcam

struct CamEntity: AppEntity, Identifiable {
    let id: String
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Webcam" }
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    static var defaultQuery = CamEntityQuery()

    init(_ spec: CamSpec) {
        id = spec.id
        name = spec.name.isEmpty ? "Webcam" : spec.name
    }
}

struct CamEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [CamEntity] {
        CamsConfig.load().filter { identifiers.contains($0.id) }.map(CamEntity.init)
    }

    func suggestedEntities() async throws -> [CamEntity] {
        CamsConfig.load().map(CamEntity.init)
    }

    func defaultResult() async -> CamEntity? {
        CamsConfig.load().first.map(CamEntity.init)
    }
}

struct SelectCamIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Webcam"
    static var description = IntentDescription("Choose which webcam this widget shows.")

    @Parameter(title: "Webcam")
    var cam: CamEntity?
}

// MARK: - Grafana source

struct SourceEntity: AppEntity, Identifiable {
    let id: String
    let name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Metrics source" }
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    static var defaultQuery = SourceEntityQuery()

    init(_ source: GrafanaSource) {
        id = source.id
        name = source.title.isEmpty ? "Metrics" : source.title
    }
}

struct SourceEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [SourceEntity] {
        GrafanaConfig.load().filter { identifiers.contains($0.id) }.map(SourceEntity.init)
    }

    func suggestedEntities() async throws -> [SourceEntity] {
        GrafanaConfig.load().map(SourceEntity.init)
    }

    func defaultResult() async -> SourceEntity? {
        GrafanaConfig.load().first.map(SourceEntity.init)
    }
}

struct SelectSourceIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Metrics source"
    static var description = IntentDescription("Choose which Grafana source this widget shows.")

    @Parameter(title: "Source")
    var source: SourceEntity?
}
