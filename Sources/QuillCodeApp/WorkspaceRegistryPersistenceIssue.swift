enum WorkspaceRegistryPersistenceKind: CaseIterable, Hashable {
    case projects
    case automations
    case savedSearches

    var label: String {
        switch self {
        case .projects:
            "Projects"
        case .automations:
            "Automations"
        case .savedSearches:
            "Saved searches"
        }
    }
}

final class WorkspaceRegistryPersistenceIssueTracker {
    private var failedKinds: Set<WorkspaceRegistryPersistenceKind> = []

    var failedKindCount: Int {
        failedKinds.count
    }

    var runtimeIssue: RuntimeIssueSurface? {
        let affectedKinds = WorkspaceRegistryPersistenceKind.allCases.filter(failedKinds.contains)
        guard !affectedKinds.isEmpty else { return nil }
        return RuntimeIssueSurface(
            severity: .error,
            title: affectedKinds.count == 1
                ? "A workspace change is not saved"
                : "Some workspace changes are not saved",
            message: "\(QuillCodeProduct.displayName) could not update one or more workspace data files. "
                + "Changes to the affected data remain available in this session, but may not "
                + "survive a relaunch. Check available disk space and app-data permissions, then "
                + "change each affected item again to retry its complete saved state.",
            diagnostics: [
                RuntimeDiagnosticSurface(
                    label: "Affected data",
                    value: affectedKinds.map(\.label).joined(separator: ", ")
                ),
                RuntimeDiagnosticSurface(label: "Private content included", value: "No")
            ]
        )
    }

    func recordFailure(for kind: WorkspaceRegistryPersistenceKind) {
        failedKinds.insert(kind)
    }

    func recordSuccess(for kind: WorkspaceRegistryPersistenceKind) {
        failedKinds.remove(kind)
    }
}
