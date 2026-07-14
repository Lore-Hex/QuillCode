import XCTest

/// Locks the runtime invariant that delegated work goes through the normal configured agent session,
/// not a one-shot model call with an empty tool catalog. Multi-step subagent turns can benefit from
/// prompt caching in the same way as main-agent turns, so this intentionally replaces the former
/// one-shot prompt-cache opt-out gate.
final class ParitySubagentPromptCacheGateTests: QuillCodeParityTestCase {
    func testSubagentWorkerUsesConfiguredMultiStepAgentSession() throws {
        let runnerSource = try Self.appSourceText(named: "WorkspaceSubagentSlashCommandRunner.swift")
        let workerSource = try Self.appSourceText(named: "WorkspaceSubagentModelWorker.swift")
        let sessionFactorySource = try Self.appSourceText(named: "WorkspaceAgentSendSessionFactory.swift")

        Self.assertSource(runnerSource, containsAll: [
            "AgentWorkspaceSubagentWorker.scheduledWorker",
            "agentSendSessionFactory("
        ])
        Self.assertSource(workerSource, containsAll: [
            "sessionFactory.makeSubagentSession",
            "try await session.run(onProgress: onProgress)",
            "result.pendingApproval",
            "pendingApproval.heldToolCall",
            "threadStore?.save",
            ").resumeApproved("
        ])
        Self.assertSource(sessionFactorySource, containsAll: [
            "func makeSubagentSession(",
            "makeSession(",
            "allowsSubagents: false"
        ])
        Self.assertSource(workerSource, excludesAll: [
            "llm.nextAction(",
            "tools: []",
            "disablingPromptCachingIfSupported"
        ])
    }
}
