import XCTest

final class ParityAgentCoreRunnerGateTests: QuillCodeParityTestCase {
    func testAgentContractsAndActionResolutionLiveOutsideRunnerFile() throws {
        let agentText = try Self.agentSourceText(named: "Agent.swift")
        let typesText = try Self.agentSourceText(named: "AgentTypes.swift")
        let resolverText = try Self.agentSourceText(named: "AgentActionResolver.swift")
        let promisedWorkText = try Self.agentSourceText(named: "AgentPromisedWorkResolver.swift")

        Self.assertSource(typesText, containsAll: [
            "public enum AgentAction",
            "public protocol LLMClient",
            "public struct AgentRunResult",
            "public typealias AgentRunProgressHandler"
        ])

        Self.assertSource(promisedWorkText, containsAll: [
            "actionByRetryingPromisedWorkIfNeeded",
            "recoveredPromisedWorkAction"
        ])

        Self.assertSource(resolverText, contains: "func nextAction")

        Self.assertSource(agentText, excludesAll: [
            "public enum AgentAction",
            "public protocol LLMClient",
            "public struct AgentRunResult",
            "func actionByRetryingPromisedWorkIfNeeded",
            "private func nextAction"
        ])
    }

    func testAgentToolStepRunnerLivesOutsideAgentRunnerFile() throws {
        let agentText = try Self.agentSourceText(named: "Agent.swift")
        let runnerText = try Self.agentSourceText(named: "AgentToolStepRunner.swift")

        Self.assertSource(runnerText, containsAll: [
            "enum AgentToolStep",
            "func runToolStep",
            "appendQueuedEvent",
            "SafetyReview"
        ])

        Self.assertSource(agentText, contains: "runToolStep(")
        Self.assertSource(agentText, excludesAll: [
            "private func runToolStep",
            "kind: .toolQueued",
            "Tool is not available in this workspace"
        ])
    }
}
