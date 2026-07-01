import XCTest

final class ParityWorkspaceToolEventGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesToolEventRecording() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let toolRunsText = try Self.appSourceText(named: "WorkspaceModelToolRuns.swift")
        let coordinatorText = try Self.appSourceText(named: "WorkspaceToolRunCoordinator.swift")
        let recorderText = try Self.appSourceText(named: "WorkspaceToolEventRecorder.swift")

        [
            "struct WorkspaceToolEventRecorder",
            "static func events",
            "static func append",
            "call.redactedForTranscript()",
            "result.ok ? .toolCompleted : .toolFailed"
        ].forEach { Self.assertSource(recorderText, contains: $0) }

        Self.assertSource(toolRunsText, contains: "WorkspaceToolRunCoordinator")
        Self.assertSource(coordinatorText, contains: "WorkspaceToolEventRecorder.append")

        [
            "WorkspaceToolEventRecorder.append(execution:",
            "call.redactedForTranscript()",
            "let resultJSON =",
            "summary: \"\\(call.name) queued\"",
            "summary: \"\\(call.name) running\""
        ].forEach { Self.assertSource(modelText, excludes: $0) }
    }
}
