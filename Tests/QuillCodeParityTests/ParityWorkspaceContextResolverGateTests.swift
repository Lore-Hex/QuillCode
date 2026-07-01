import XCTest

final class ParityWorkspaceContextResolverGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesContextResolving() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let resolverText = try Self.appSourceText(named: "WorkspaceContextResolver.swift")
        let refresherText = try Self.appSourceText(named: "WorkspaceProjectContextRefresher.swift")
        let matcherText = try Self.appSourceText(named: "LocalEnvironmentActionMatcher.swift")

        Self.assertSource(resolverText, containsAll: [
            "struct WorkspaceActiveContextSources",
            "struct WorkspaceContextResolver",
            "func instructions(for projectID:",
            "func memoryNotes(for projectID:",
            "func activeSources(for thread:",
            "func selectedLocalAction(withID",
            "func selectedLocalAction(matching",
            "LocalEnvironmentActionMatcher.action(withID",
            "LocalEnvironmentActionMatcher.action(matching"
        ])
        Self.assertSource(matcherText, contains: "enum LocalEnvironmentActionMatcher")
        Self.assertSource(surfaceText, contains: "WorkspaceContextResolver(")
        Self.assertSource(refresherText, contains: "WorkspaceContextResolver(")
        Self.assertSource(modelText, excludesAll: [
            "WorkspaceContextResolver(",
            "private func instructions(for projectID",
            "private func memoryNotes(for projectID",
            "private func localAction(withID",
            "private func localAction(matching",
            "private static func normalizedActionName"
        ])
        Self.assertSource(surfaceText, excludesAll: [
            "thread.instructions.isEmpty",
            "thread.memories.isEmpty",
            "selectedProject?.instructions ?? []",
            "root.globalMemories +"
        ])
    }
}
