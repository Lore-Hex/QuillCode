import XCTest

final class ParityWorkspaceExecutionAgentContextGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesAgentRunContextAssembly() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let agentSessionText = try Self.appSourceText(named: "WorkspaceModelAgentSession.swift")
        let builderText = try Self.appSourceText(named: "WorkspaceAgentRunContextBuilder.swift")
        let factoryText = try Self.appSourceText(named: "WorkspaceAgentSendSessionFactory.swift")
        let memoryExecutorText = try Self.appSourceText(named: "WorkspaceMemoryRememberToolExecutor.swift")

        XCTAssertTrue(factoryText.contains("WorkspaceAgentRunContextBuilder("), "The send-session factory should delegate per-run tool assembly.")
        XCTAssertTrue(agentSessionText.contains("WorkspaceAgentSendSessionFactory("), "WorkspaceModel agent-session APIs should delegate per-run session assembly.")
        XCTAssertTrue(builderText.contains("configuredRunner(from runner: AgentRunner, modelID: String? = nil)"), "Agent run context builder should own runner configuration.")
        XCTAssertTrue(builderText.contains("ToolDefinition.planUpdate"), "Agent run context builder should attach the plan tool.")
        XCTAssertTrue(builderText.contains("ToolDefinition.handoffUpdate"), "Agent run context builder should attach the handoff summary tool.")
        XCTAssertTrue(builderText.contains("ToolDefinition.browserInspect"), "Agent run context builder should attach the browser tool.")
        XCTAssertTrue(builderText.contains("ToolDefinition.browserOpen"), "Agent run context builder should attach browser navigation.")
        XCTAssertTrue(builderText.contains("ToolDefinition.browserClick"), "Agent run context builder should attach visible-browser click.")
        XCTAssertTrue(builderText.contains("ToolDefinition.browserType"), "Agent run context builder should attach visible-browser typing.")
        XCTAssertTrue(builderText.contains("WorkspaceBrowserToolExecutor.execute"), "Browser tool execution should stay in the focused browser executor.")
        XCTAssertTrue(builderText.contains("ToolDefinition.computerUseDefinitions"), "Agent run context builder should attach Computer Use tools only when available.")
        XCTAssertTrue(builderText.contains("WorkspaceMemoryRememberToolExecutor.executionOverride"), "Agent run context builder should delegate memory tool execution.")
        XCTAssertTrue(memoryExecutorText.contains("didSaveMemory(in thread: ChatThread)"), "Memory save detection should live beside memory tool execution.")
        XCTAssertFalse(modelText.contains("WorkspaceAgentRunContextBuilder("), "WorkspaceModel should not construct the run-context builder inline.")
        XCTAssertFalse(modelText.contains("activeRunner.additionalToolDefinitions"), "WorkspaceModel should not assemble per-run additional tool definitions inline.")
        XCTAssertFalse(modelText.contains("private func activityToolExecutionOverride"), "WorkspaceModel should not own Activity tool override assembly.")
        XCTAssertFalse(modelText.contains("private func planToolExecutionOverride"), "WorkspaceModel should not own plan tool override assembly.")
        XCTAssertFalse(modelText.contains("private func browserToolExecutionOverride"), "WorkspaceModel should not own browser tool override assembly.")
        XCTAssertFalse(modelText.contains("private func memoryToolExecutionOverride"), "WorkspaceModel should not own memory tool override assembly.")
        XCTAssertFalse(modelText.contains("private nonisolated static func didSaveMemory"), "WorkspaceModel should not own memory-save event parsing.")
    }

    func testWorkspaceModelDelegatesAgentSendSession() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let agentSessionText = try Self.appSourceText(named: "WorkspaceModelAgentSession.swift")
        let factoryText = try Self.appSourceText(named: "WorkspaceAgentSendSessionFactory.swift")
        let sessionText = try Self.appSourceText(named: "WorkspaceAgentSendSession.swift")

        XCTAssertTrue(sessionText.contains("struct WorkspaceAgentSendSession"), "Agent send lifecycle should live in a focused session.")
        XCTAssertTrue(sessionText.contains("func run("), "Agent send lifecycle should be directly testable.")
        XCTAssertTrue(sessionText.contains("runner.send("), "The session should own the runner send call.")
        XCTAssertTrue(sessionText.contains("WorkspaceMemoryRememberToolExecutor.didSaveMemory"), "The session should report whether the run saved memory.")
        XCTAssertTrue(factoryText.contains("WorkspaceAgentSendSession("), "The factory should own agent send session construction.")
        XCTAssertTrue(agentSessionText.contains("WorkspaceAgentSendSessionFactory("), "WorkspaceModel agent-session APIs should delegate agent send execution setup.")
        XCTAssertFalse(modelText.contains("WorkspaceAgentSendSession("), "WorkspaceModel should not construct agent send sessions inline.")
        XCTAssertFalse(modelText.contains("activeRunner.send("), "WorkspaceModel should not own the low-level send call.")
        XCTAssertFalse(modelText.contains("WorkspaceMemoryRememberToolExecutor.didSaveMemory(in: thread)"), "WorkspaceModel should not inspect memory events after each send.")
    }

}
