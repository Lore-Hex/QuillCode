import XCTest

/// Locks the runtime invariant that delegated work goes through the normal configured agent session,
/// not a one-shot model call with an empty tool catalog. Multi-step subagent turns can benefit from
/// prompt caching in the same way as main-agent turns, so this intentionally replaces the former
/// one-shot prompt-cache opt-out gate.
final class ParitySubagentPromptCacheGateTests: QuillCodeParityTestCase {
    func testSubagentWorkerUsesConfiguredMultiStepAgentSession() throws {
        let runnerSource = try Self.appSourceText(named: "WorkspaceSubagentSlashCommandRunner.swift")
        let workerSource = try Self.appSourceText(named: "WorkspaceSubagentModelWorker.swift")

        Self.assertSource(runnerSource, containsAll: [
            "AgentWorkspaceSubagentWorker.scheduledWorker",
            "agentSendSessionFactory("
        ])
        Self.assertSource(workerSource, containsAll: [
            "sessionFactory.makeSession",
            "try await session.run()",
            "result.pendingApproval",
            "sessionFactory.resumeApproved("
        ])
        Self.assertSource(workerSource, excludesAll: [
            "llm.nextAction(",
            "tools: []",
            "disablingPromptCachingIfSupported"
        ])
    }
}
