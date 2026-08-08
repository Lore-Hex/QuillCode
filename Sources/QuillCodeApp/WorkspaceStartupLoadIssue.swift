import Foundation

public enum WorkspaceStartupDataKind: String, CaseIterable, Sendable, Hashable {
    case workspaceStorage
    case configuration
    case chats
    case projects
    case automations
    case savedSearches

    var label: String {
        switch self {
        case .workspaceStorage:
            "Workspace storage"
        case .configuration:
            "Settings"
        case .chats:
            "Chats"
        case .projects:
            "Projects"
        case .automations:
            "Automations"
        case .savedSearches:
            "Saved searches"
        }
    }
}

public struct WorkspaceStartupLoadIssue: Sendable, Hashable {
    private var loadedThreadCount: Int
    private var threadLoadIssue: WorkspaceThreadLoadIssue?
    private var unreadableDataKinds: [WorkspaceStartupDataKind]

    public init?(
        loadedThreadCount: Int,
        threadLoadIssue: WorkspaceThreadLoadIssue? = nil,
        unreadableDataKinds: [WorkspaceStartupDataKind]
    ) {
        let requestedKinds = Set(unreadableDataKinds)
        let normalizedKinds = WorkspaceStartupDataKind.allCases.filter(requestedKinds.contains)
        guard threadLoadIssue != nil || !normalizedKinds.isEmpty else { return nil }
        self.loadedThreadCount = max(0, loadedThreadCount)
        self.threadLoadIssue = threadLoadIssue
        self.unreadableDataKinds = normalizedKinds
    }

    var runtimeIssue: RuntimeIssueSurface {
        if unreadableDataKinds.isEmpty, let threadLoadIssue {
            return threadLoadIssue.runtimeIssue
        }
        let storageUnavailable = unreadableDataKinds.contains(.workspaceStorage)
        return RuntimeIssueSurface(
            severity: .warning,
            title: storageUnavailable
                ? "Workspace storage could not be opened"
                : "Some saved workspace data could not be loaded",
            message: storageUnavailable ? storageUnavailableMessage : partialRecoveryMessage,
            actionLabel: "Review diagnostics",
            recovery: RuntimeRecoveryTelemetry(
                route: .settings,
                reason: .savedWorkspaceDataUnreadable,
                commandID: "settings"
            ),
            diagnostics: diagnostics
        )
    }

    private var storageUnavailableMessage: String {
        "Quill Cowork started in recovery mode without changing your saved workspace data. " +
            "Review storage permissions and available disk space before continuing."
    }

    private var partialRecoveryMessage: String {
        let healthyChats = loadedThreadCount == 0
            ? ""
            : " Your \(loadedThreadCount) saved \(loadedThreadCount == 1 ? "chat is" : "chats are") still available."
        return "Quill Cowork loaded every healthy record and used safe defaults for the affected data." +
            healthyChats + " The original files were left unchanged so they can be recovered."
    }

    private var diagnostics: [RuntimeDiagnosticSurface] {
        var rows = [
            RuntimeDiagnosticSurface(
                label: "Affected data",
                value: unreadableDataKinds.map(\.label).joined(separator: ", ")
            ),
            RuntimeDiagnosticSurface(label: "Loaded chats", value: String(loadedThreadCount)),
        ]
        if let threadIssue = threadLoadIssue?.runtimeIssue {
            rows.append(contentsOf: threadIssue.diagnostics.compactMap { diagnostic in
                switch diagnostic.label {
                case "Loaded chats", "Recovery":
                    return nil
                case "Affected files":
                    return RuntimeDiagnosticSurface(label: "Affected chat files", value: diagnostic.value)
                default:
                    return diagnostic
                }
            })
        }
        rows.append(RuntimeDiagnosticSurface(
            label: "Recovery",
            value: "Back up ~/.quillcode, then run quill-code doctor."
        ))
        return rows
    }
}
