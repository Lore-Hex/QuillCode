import QuillCodeCore

@MainActor
extension QuillCodeDesktopController {
    func discoverAgentImport() async -> AgentImportPreview {
        await model.discoverAgentImport()
    }

    func performAgentImport(_ selection: AgentImportSelection) async -> AgentImportOutcome {
        let outcome = await model.performAgentImport(selection)
        refresh()
        return outcome
    }
}
