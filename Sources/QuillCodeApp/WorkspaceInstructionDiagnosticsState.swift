import QuillCodeCore

@MainActor
extension QuillCodeWorkspaceModel {
    var activeInstructionDiagnostics: [ProjectInstructionDiagnostic] {
        ProjectInstructionDiagnosticsBuilder.diagnostics(for: activeInstructionSources)
    }

    var activeInstructionDiagnosticIDs: Set<String> {
        Set(activeInstructionDiagnostics.map(\.id))
    }

    var activeInstructionResolutionProjectIndex: Array<ProjectRef>.Index? {
        let activeProjectID = selectedThread?.projectID ?? root.selectedProjectID
        guard let activeProjectID else { return nil }
        return root.projects.firstIndex { $0.id == activeProjectID }
    }

    private var activeInstructionSources: [ProjectInstruction] {
        WorkspaceContextResolver(
            projects: root.projects,
            globalMemories: root.globalMemories,
            selectedProject: selectedProject
        ).activeSources(for: selectedThread).instructions
    }
}
