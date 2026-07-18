import XCTest

final class ParityAppServerThreadControlGateTests: QuillCodeParityTestCase {
    func testThreadControlsStayWiredThroughRuntimePersistenceTestsSmokeAndDocs() throws {
        let root = Self.packageRoot()
        let session = try text(root, "Sources/QuillCodeCLI/AppServerSession.swift")
        let controls = try text(
            root,
            "Sources/QuillCodeCLI/AppServerSessionThreadControls.swift"
        )
        let metadata = try text(
            root,
            "Sources/QuillCodeCLI/AppServerSessionThreadMetadata.swift"
        )
        let settingsUpdate = try text(
            root,
            "Sources/QuillCodeCLI/AppServerSessionThreadSettingsUpdate.swift"
        )
        let models = try text(
            root,
            "Sources/QuillCodeCLI/AppServerThreadControlModels.swift"
        )
        let repository = try text(
            root,
            "Sources/QuillCodeCLI/AppServerThreadRepository.swift"
        )
        let turnExecution = try text(
            root,
            "Sources/QuillCodeCLI/AppServerSessionTurnExecution.swift"
        )
        let tests = try text(
            root,
            "Tests/QuillCodeCLITests/AppServerThreadControlTests.swift"
        )
        let smoke = try text(root, "scripts/app-server-smoke.sh")
        let parity = try Self.docsText(named: "CODEX_PARITY_MATRIX.md")
        let decisions = try Self.docsText(named: "DECISIONS.md")
        let research = try Self.docsText(named: "CODEX_RESEARCH.md")

        Self.assertSource(session, containsAll: [
            "case \"thread/unsubscribe\"",
            "case \"thread/increment_elicitation\"",
            "case \"thread/decrement_elicitation\"",
            "case \"thread/metadata/update\"",
            "case \"thread/settings/update\"",
            "case \"thread/memoryMode/set\"",
            "notificationsAfterResponse"
        ])
        Self.assertSource(controls, containsAll: [
            "func unsubscribeThread",
            "addingReportingOverflow",
            "func setThreadMemoryMode"
        ])
        Self.assertSource(metadata, containsAll: [
            "func updateThreadMetadata",
            "struct GitInfoPatch"
        ])
        Self.assertSource(settingsUpdate, containsAll: [
            "func updateThreadSettings",
            "thread/settings/updated",
            "AppServerSandboxPolicyParser.parse"
        ])
        Self.assertSource(models, containsAll: [
            "struct AppServerThreadGitInfo",
            "enum AppServerThreadMemoryMode",
            "struct AppServerCollaborationMode",
            "struct AppServerSandboxPolicy"
        ])
        Self.assertSource(repository, containsAll: [
            "var gitInfo: AppServerThreadGitInfo?",
            "var collaborationMode: AppServerCollaborationMode?",
            "var effectiveMemoryMode: AppServerThreadMemoryMode",
            "var effectiveSandboxPolicy: AppServerSandboxPolicy"
        ])
        Self.assertSource(turnExecution, containsAll: [
            "active.settings.effectiveMemoryMode == .enabled",
            "memoryFeatureEnabled",
            "if !memoriesEnabled",
            "result.thread.memories = durableMemories"
        ])
        Self.assertSource(tests, containsAll: [
            "testFirstOperationOnPersistedThreadSubscribesWithoutUndoingExplicitUnsubscribe",
            "testUnsubscribeKeepsThreadLoadedAndFiltersOnlyDetailedEventsUntilResume",
            "testElicitationCountersAreConnectionScopedAndMatchCodexErrors",
            "testGitMetadataPatchPersistsOmittedAndClearedFields",
            "testSettingsUpdatePersistsFullProjectionAndNotifiesAfterResponseOnlyOnChange",
            "testExternalSandboxPolicyIsExplicitUnsupportedBoundary",
            "testDisabledMemoryIsHiddenFromModelWithoutDeletingStoredNotes"
        ])
        Self.assertSource(smoke, containsAll: [
            "thread/increment_elicitation",
            "thread/decrement_elicitation",
            "thread/metadata/update",
            "thread/settings/update",
            "thread/memoryMode/set",
            "thread/unsubscribe"
        ])
        Self.assertSource(parity, containsAll: [
            "thread/settings/update",
            "thread/memoryMode/set"
        ])
        Self.assertSource(
            decisions,
            contains: "Thread controls separate connection state from durable settings"
        )
        Self.assertSource(research, containsAll: [
            "thread/increment_elicitation",
            "thread/settings/updated"
        ])
    }

    private func text(_ root: URL, _ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
