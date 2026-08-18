final class WorkspaceSettingsPersistenceIssueTracker {
    private var failedKinds: Set<WorkspaceSettingsPersistenceKind> = []

    var failedKindCount: Int {
        failedKinds.count
    }

    var runtimeIssue: RuntimeIssueSurface? {
        let affectedKinds = WorkspaceSettingsPersistenceKind.allCases.filter(failedKinds.contains)
        guard !affectedKinds.isEmpty else { return nil }
        return RuntimeIssueSurface(
            severity: .error,
            title: affectedKinds.count == 1
                ? "A settings change is not saved"
                : "Some settings changes are not saved",
            message: "\(QuillCodeProduct.displayName) could not safely update one or more settings files. "
                + "Affected changes may remain available only in this session or may have been "
                + "left unapplied to protect the previous configuration. Check available disk "
                + "space and app-data permissions, then retry each affected setting.",
            diagnostics: [
                RuntimeDiagnosticSurface(
                    label: "Affected data",
                    value: affectedKinds.map(\.label).joined(separator: ", ")
                ),
                RuntimeDiagnosticSurface(label: "Private content included", value: "No")
            ]
        )
    }

    func recordFailure(for kinds: Set<WorkspaceSettingsPersistenceKind>) {
        failedKinds.formUnion(kinds)
    }

    func recordSuccess(for kinds: Set<WorkspaceSettingsPersistenceKind>) {
        failedKinds.subtract(kinds)
    }
}

public extension QuillCodeWorkspaceModel {
    func recordSettingsPersistenceFailure(
        _ kinds: Set<WorkspaceSettingsPersistenceKind>
    ) {
        settingsPersistenceIssueTracker.recordFailure(for: kinds)
    }

    func recordSettingsPersistenceSuccess(
        _ kinds: Set<WorkspaceSettingsPersistenceKind>
    ) {
        settingsPersistenceIssueTracker.recordSuccess(for: kinds)
    }
}
