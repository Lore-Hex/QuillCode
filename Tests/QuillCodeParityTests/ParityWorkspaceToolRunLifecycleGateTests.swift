import XCTest

final class ParityWorkspaceToolRunLifecycleGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesToolRunPreparation() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let toolRunsText = try Self.appSourceText(named: "WorkspaceModelToolRuns.swift")
        let coordinatorText = try Self.appSourceText(named: "WorkspaceToolRunCoordinator.swift")
        let preparerText = try Self.appSourceText(named: "WorkspaceToolRunPreparer.swift")
        let sharedPreparerText = try Self.appSourceText(named: "WorkspaceThreadContextPreparer.swift")
        let runBody = try Self.toolRunCoordinatorBody(in: coordinatorText)

        Self.assertSource(toolRunsText, contains: "extension QuillCodeWorkspaceModel")
        Self.assertSource(
            toolRunsText,
            contains: "WorkspaceToolRunCoordinator(model: self, workspaceRoot: workspaceRoot).run(call)"
        )
        Self.assertSource(modelText, excludes: "public func runToolCall")

        [
            "enum WorkspaceToolRunPreparer",
            "static func effectiveProjectID",
            "static func syncThreadContext",
            "WorkspaceThreadContextPreparer.effectiveProjectID",
            "WorkspaceThreadContextPreparer.syncThreadContext"
        ].forEach { Self.assertSource(preparerText, contains: $0) }

        Self.assertSource(sharedPreparerText, contains: "enum WorkspaceThreadContextPreparer")
        Self.assertSource(preparerText, excludes: "WorkspaceProjectContextRefresher.syncThreadContext")
        Self.assertSource(coordinatorText, contains: "WorkspaceToolRunPreparer.syncThreadContext")
        Self.assertSource(runBody, contains: "WorkspaceToolRunPreparer.effectiveProjectID")
        Self.assertSource(runBody, contains: "syncSelectedThreadContextForToolRun")

        [
            "WorkspaceToolRunPreparer.effectiveProjectID",
            "workspaceThreadContext(",
            "thread.instructions =",
            "thread.memories ="
        ].forEach { needle in
            let source = needle == "WorkspaceToolRunPreparer.effectiveProjectID" ? toolRunsText : runBody
            Self.assertSource(source, excludes: needle)
        }
    }

    func testWorkspaceModelDelegatesToolRunLifecyclePlanning() throws {
        let toolRunsText = try Self.appSourceText(named: "WorkspaceModelToolRuns.swift")
        let coordinatorText = try Self.appSourceText(named: "WorkspaceToolRunCoordinator.swift")
        let lifecycleText = try Self.appSourceText(named: "WorkspaceToolRunLifecyclePlanner.swift")
        let runBody = try Self.toolRunCoordinatorBody(in: coordinatorText)

        Self.assertSource(toolRunsText, contains: "WorkspaceToolRunCoordinator")
        Self.assertSource(coordinatorText, contains: "struct WorkspaceToolRunCoordinator")

        [
            "enum WorkspaceToolRunLifecyclePlanner",
            "static func started",
            "static func finished"
        ].forEach { Self.assertSource(lifecycleText, contains: $0) }

        [
            "WorkspaceToolRunLifecyclePlanner.started",
            "WorkspaceToolRunLifecyclePlanner.finished"
        ].forEach { Self.assertSource(runBody, contains: $0) }

        Self.assertSource(toolRunsText, excludes: "WorkspaceToolRunLifecyclePlanner.started")
        Self.assertSource(runBody, excludes: "TopBarAgentStatusLabel.running")
        Self.assertSource(runBody, excludes: "execution.ok ?")
    }

    private static func toolRunCoordinatorBody(in coordinatorText: String) throws -> String {
        let runStart = try XCTUnwrap(coordinatorText.range(of: "func run(_ call: ToolCall)"))
        let runEnd = try XCTUnwrap(coordinatorText.range(
            of: "private func syncSelectedThreadContextForToolRun",
            range: runStart.upperBound..<coordinatorText.endIndex
        ))
        return String(coordinatorText[runStart.lowerBound..<runEnd.lowerBound])
    }
}
