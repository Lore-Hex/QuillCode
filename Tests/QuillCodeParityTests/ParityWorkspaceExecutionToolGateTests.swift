import XCTest

final class ParityWorkspaceExecutionToolGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesToolEventRecording() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let toolRunsText = try Self.appSourceText(named: "WorkspaceModelToolRuns.swift")
        let coordinatorText = try Self.appSourceText(named: "WorkspaceToolRunCoordinator.swift")
        let recorderText = try Self.appSourceText(named: "WorkspaceToolEventRecorder.swift")

        XCTAssertTrue(recorderText.contains("struct WorkspaceToolEventRecorder"), "Tool audit event construction should live in a focused recorder.")
        XCTAssertTrue(recorderText.contains("static func events"), "Tool event construction should be directly testable.")
        XCTAssertTrue(recorderText.contains("static func append"), "Thread mutation should be a thin append helper.")
        XCTAssertTrue(recorderText.contains("call.redactedForTranscript()"), "Tool call redaction should live beside queued-event construction.")
        XCTAssertTrue(recorderText.contains("result.ok ? .toolCompleted : .toolFailed"), "Completion/failure classification should live beside tool event construction.")
        XCTAssertTrue(toolRunsText.contains("WorkspaceToolRunCoordinator"), "The tool-run extension should delegate orchestration to the focused coordinator.")
        XCTAssertTrue(coordinatorText.contains("WorkspaceToolEventRecorder.append"), "The tool-run coordinator should delegate tool audit event recording.")
        XCTAssertFalse(modelText.contains("WorkspaceToolEventRecorder.append(execution:"), "WorkspaceModel.swift should not own generic tool audit event recording.")
        XCTAssertFalse(modelText.contains("call.redactedForTranscript()"), "WorkspaceModel should not own tool call redaction for transcript events.")
        XCTAssertFalse(modelText.contains("let resultJSON ="), "WorkspaceModel should not own tool result JSON payload construction.")
        XCTAssertFalse(modelText.contains("summary: \"\\(call.name) queued\""), "WorkspaceModel should not construct queued tool summaries directly.")
        XCTAssertFalse(modelText.contains("summary: \"\\(call.name) running\""), "WorkspaceModel should not construct running tool summaries directly.")
    }

    func testWorkspaceModelDelegatesToolCallExecutionRouting() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let toolRunsText = try Self.appSourceText(named: "WorkspaceModelToolRuns.swift")
        let coordinatorText = try Self.appSourceText(named: "WorkspaceToolRunCoordinator.swift")
        let factoryText = try Self.appSourceText(named: "WorkspaceToolCallExecutorFactory.swift")
        let executorText = try Self.appSourceText(named: "WorkspaceToolCallExecutor.swift")

        XCTAssertTrue(executorText.contains("struct WorkspaceToolCallExecutor"), "Tool-call routing should live in a focused executor.")
        XCTAssertTrue(executorText.contains("WorkspaceBrowserToolExecutor.execute"), "The executor should own browser tool routing.")
        XCTAssertTrue(executorText.contains("PlanUpdateToolExecutor.execute"), "The executor should own plan update routing.")
        XCTAssertTrue(executorText.contains("HandoffUpdateToolExecutor.execute"), "The executor should own handoff summary update routing.")
        XCTAssertTrue(executorText.contains("SubagentProgressToolExecutor.execute"), "The executor should own subagent progress update routing.")
        XCTAssertTrue(executorText.contains("WorkspaceRemoteProjectToolExecutor.execute"), "The executor should own remote project routing.")
        XCTAssertTrue(executorText.contains("ToolDefinition.applyPatch.name"), "The executor should own apply-patch follow-up routing.")
        XCTAssertTrue(toolRunsText.contains("WorkspaceToolRunCoordinator"), "The tool-run extension should delegate orchestration to the focused coordinator.")
        XCTAssertTrue(factoryText.contains("enum WorkspaceToolCallExecutorFactory"), "Shared executor construction should live in a focused factory.")
        XCTAssertTrue(factoryText.contains("WorkspaceToolCallExecutor("), "The factory should build the focused executor.")
        XCTAssertTrue(coordinatorText.contains("WorkspaceToolCallExecutorFactory.executor"), "The tool-run coordinator should reuse the shared executor factory.")
        XCTAssertFalse(modelText.contains("func workspaceToolCallExecutor"), "WorkspaceModel.swift should not own tool execution routing.")
        XCTAssertFalse(toolRunsText.contains("func workspaceToolCallExecutor"), "The thin tool-run extension should not own tool execution routing.")
        XCTAssertFalse(modelText.contains("call.name == ToolDefinition.browserInspect.name"), "WorkspaceModel should not branch on browser inspect tool execution.")
        XCTAssertFalse(modelText.contains("call.name == ToolDefinition.browserOpen.name"), "WorkspaceModel should not branch on browser open tool execution.")
        XCTAssertFalse(modelText.contains("call.name == ToolDefinition.planUpdate.name"), "WorkspaceModel should not branch on plan update tool execution.")
        XCTAssertFalse(modelText.contains("call.name == ToolDefinition.handoffUpdate.name"), "WorkspaceModel should not branch on handoff update tool execution.")
        XCTAssertFalse(modelText.contains("private func appendReviewDiffAfterPatchIfNeeded"), "WorkspaceModel should not own apply-patch review diff follow-up routing.")
        XCTAssertFalse(modelText.contains("private func executeReviewGitToolCall"), "WorkspaceModel should not own parallel review git routing.")
    }

    func testWorkspaceModelDelegatesToolRunPreparation() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let toolRunsText = try Self.appSourceText(named: "WorkspaceModelToolRuns.swift")
        let coordinatorText = try Self.appSourceText(named: "WorkspaceToolRunCoordinator.swift")
        let preparerText = try Self.appSourceText(named: "WorkspaceToolRunPreparer.swift")
        let sharedPreparerText = try Self.appSourceText(named: "WorkspaceThreadContextPreparer.swift")
        let runStart = try XCTUnwrap(coordinatorText.range(of: "func run(_ call: ToolCall)"))
        let runEnd = try XCTUnwrap(coordinatorText.range(
            of: "private func syncSelectedThreadContextForToolRun",
            range: runStart.upperBound..<coordinatorText.endIndex
        ))
        let runBody = String(coordinatorText[runStart.lowerBound..<runEnd.lowerBound])

        XCTAssertTrue(toolRunsText.contains("extension QuillCodeWorkspaceModel"), "Generic tool-run APIs should live in a focused model extension.")
        XCTAssertTrue(toolRunsText.contains("WorkspaceToolRunCoordinator(model: self, workspaceRoot: workspaceRoot).run(call)"), "The extension should delegate generic tool-run orchestration.")
        XCTAssertFalse(modelText.contains("public func runToolCall"), "WorkspaceModel.swift should not own the generic tool-run API body.")
        XCTAssertTrue(preparerText.contains("enum WorkspaceToolRunPreparer"), "Tool-run context preparation should live in a focused helper.")
        XCTAssertTrue(preparerText.contains("static func effectiveProjectID"), "Effective tool-run project selection should be directly testable.")
        XCTAssertTrue(preparerText.contains("static func syncThreadContext"), "Tool-run thread context sync should be directly testable.")
        XCTAssertTrue(sharedPreparerText.contains("enum WorkspaceThreadContextPreparer"), "Generic thread context preparation should live in a shared helper.")
        XCTAssertTrue(preparerText.contains("WorkspaceThreadContextPreparer.effectiveProjectID"), "Tool-run project selection should reuse shared context preparation.")
        XCTAssertTrue(preparerText.contains("WorkspaceThreadContextPreparer.syncThreadContext"), "Tool-run context sync should reuse shared context preparation.")
        XCTAssertFalse(preparerText.contains("WorkspaceProjectContextRefresher.syncThreadContext"), "Tool-run preparation should not sync project context directly.")
        XCTAssertTrue(runBody.contains("WorkspaceToolRunPreparer.effectiveProjectID"), "The coordinator should delegate tool-run project selection.")
        XCTAssertTrue(runBody.contains("syncSelectedThreadContextForToolRun"), "The coordinator should delegate selected-thread context sync to a named helper.")
        XCTAssertTrue(coordinatorText.contains("WorkspaceToolRunPreparer.syncThreadContext"), "The tool-run coordinator should delegate tool-run thread context sync.")
        XCTAssertFalse(toolRunsText.contains("WorkspaceToolRunPreparer.effectiveProjectID"), "The thin tool-run extension should not own project selection.")
        XCTAssertFalse(runBody.contains("workspaceThreadContext("), "The coordinator should not rebuild thread context inline.")
        XCTAssertFalse(runBody.contains("thread.instructions ="), "The coordinator should not assign instruction snapshots inline.")
        XCTAssertFalse(runBody.contains("thread.memories ="), "The coordinator should not assign memory snapshots inline.")
    }

    func testWorkspaceModelDelegatesToolRunLifecyclePlanning() throws {
        let toolRunsText = try Self.appSourceText(named: "WorkspaceModelToolRuns.swift")
        let coordinatorText = try Self.appSourceText(named: "WorkspaceToolRunCoordinator.swift")
        let lifecycleText = try Self.appSourceText(named: "WorkspaceToolRunLifecyclePlanner.swift")
        let runStart = try XCTUnwrap(coordinatorText.range(of: "func run(_ call: ToolCall)"))
        let runEnd = try XCTUnwrap(coordinatorText.range(
            of: "private func syncSelectedThreadContextForToolRun",
            range: runStart.upperBound..<coordinatorText.endIndex
        ))
        let runBody = String(coordinatorText[runStart.lowerBound..<runEnd.lowerBound])

        XCTAssertTrue(toolRunsText.contains("WorkspaceToolRunCoordinator"), "The tool-run extension should delegate orchestration to the focused coordinator.")
        XCTAssertTrue(coordinatorText.contains("struct WorkspaceToolRunCoordinator"), "Generic tool-run sequencing should live in a focused coordinator.")
        XCTAssertTrue(lifecycleText.contains("enum WorkspaceToolRunLifecyclePlanner"), "Tool-run lifecycle status should live in a focused planner.")
        XCTAssertTrue(lifecycleText.contains("static func started"), "Tool-run start lifecycle should be directly testable.")
        XCTAssertTrue(lifecycleText.contains("static func finished"), "Tool-run finish lifecycle should be directly testable.")
        XCTAssertTrue(runBody.contains("WorkspaceToolRunLifecyclePlanner.started"), "The coordinator should delegate tool-run start lifecycle.")
        XCTAssertTrue(runBody.contains("WorkspaceToolRunLifecyclePlanner.finished"), "The coordinator should delegate tool-run finish lifecycle.")
        XCTAssertFalse(toolRunsText.contains("WorkspaceToolRunLifecyclePlanner.started"), "The thin tool-run extension should not own lifecycle planning.")
        XCTAssertFalse(runBody.contains("TopBarAgentStatusLabel.running"), "The coordinator should not choose started status inline.")
        XCTAssertFalse(runBody.contains("execution.ok ?"), "The coordinator should not choose final status inline.")
    }

    func testWorkspaceModelDelegatesTerminalLifecyclePlanning() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let terminalText = try Self.appSourceText(named: "WorkspaceModelTerminal.swift")
        let lifecycleText = try Self.appSourceText(named: "WorkspaceTerminalLifecyclePlanner.swift")

        XCTAssertTrue(terminalText.contains("extension QuillCodeWorkspaceModel"), "Terminal workspace APIs should live in a focused model extension.")
        XCTAssertTrue(lifecycleText.contains("enum WorkspaceTerminalLifecyclePlanner"), "Terminal lifecycle status should live in a focused planner.")
        XCTAssertTrue(lifecycleText.contains("static func started"), "Terminal start lifecycle should be directly testable.")
        XCTAssertTrue(lifecycleText.contains("static func missingExecutionContext"), "Terminal missing-context lifecycle should be directly testable.")
        XCTAssertTrue(lifecycleText.contains("static func finished"), "Terminal finish lifecycle should be directly testable.")
        XCTAssertTrue(terminalText.contains("WorkspaceTerminalLifecyclePlanner.started"), "Terminal API extension should delegate terminal start lifecycle.")
        XCTAssertTrue(terminalText.contains("WorkspaceTerminalLifecyclePlanner.missingExecutionContext"), "Terminal API extension should delegate terminal missing-context lifecycle.")
        XCTAssertTrue(terminalText.contains("WorkspaceTerminalLifecyclePlanner.stopped"), "Terminal API extension should delegate terminal stopped lifecycle.")
        XCTAssertTrue(terminalText.contains("WorkspaceTerminalLifecyclePlanner.cancelled"), "Terminal API extension should delegate terminal cancelled lifecycle.")
        XCTAssertTrue(terminalText.contains("WorkspaceTerminalLifecyclePlanner.finished"), "Terminal API extension should delegate terminal finish lifecycle.")
        XCTAssertFalse(modelText.contains("public func runTerminalCommand"), "WorkspaceModel.swift should not own terminal run APIs.")
        XCTAssertFalse(modelText.contains("public func clearTerminalHistory"), "WorkspaceModel.swift should not own terminal history APIs.")
        XCTAssertFalse(terminalText.contains("TopBarAgentStatusLabel.terminal"), "runTerminalCommand should not choose started status inline.")
        XCTAssertFalse(terminalText.contains("TopBarAgentStatusLabel.stopped"), "runTerminalCommand should not choose stopped status inline.")
        XCTAssertFalse(terminalText.contains("result.ok ?"), "runTerminalCommand should not choose final status inline.")
    }

    func testWorkspaceModelDelegatesActiveWorkStopPlanning() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let activeWorkText = try Self.appSourceText(named: "WorkspaceModelActiveWork.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceActiveWorkStopPlanner.swift")

        XCTAssertTrue(activeWorkText.contains("extension QuillCodeWorkspaceModel"), "Active-work APIs should live in a focused model extension.")
        XCTAssertTrue(plannerText.contains("enum WorkspaceActiveWorkStopPlanner"), "Stop/disconnect lifecycle status should live in a focused planner.")
        XCTAssertTrue(plannerText.contains("static func cancel"), "Cancel lifecycle should be directly testable.")
        XCTAssertTrue(plannerText.contains("static func disconnectAll"), "Disconnect lifecycle should be directly testable.")
        XCTAssertTrue(activeWorkText.contains("WorkspaceActiveWorkStopPlanner.cancel"), "Active-work extension should delegate cancel lifecycle.")
        XCTAssertTrue(activeWorkText.contains("WorkspaceActiveWorkStopPlanner.disconnectAll"), "Active-work extension should delegate disconnect lifecycle.")
        XCTAssertTrue(activeWorkText.contains("applyActiveWorkStopPlan"), "Active-work extension should share active-work stop plan application.")
        XCTAssertFalse(modelText.contains("public func cancelActiveWork"), "WorkspaceModel.swift should not own active-work cancel APIs.")
        XCTAssertFalse(modelText.contains("public func disconnectAll"), "WorkspaceModel.swift should not own active-work disconnect APIs.")
        XCTAssertFalse(modelText.contains("stopActiveWorkspaceWork"), "WorkspaceModel.swift should not own active-work stop aggregation.")
        XCTAssertFalse(activeWorkText.contains("TopBarAgentStatusLabel.stopped"), "Active-work extension should not choose stopped status inline for cancellation.")
        XCTAssertFalse(activeWorkText.contains("TopBarAgentStatusLabel.idle"), "Active-work extension should not choose idle status inline for disconnect.")
        XCTAssertFalse(activeWorkText.contains("? TopBarAgentStatusLabel"), "Active-work extension should not choose stop status with inline ternaries.")
    }

    func testWorkspaceModelDelegatesShellToolCallPlanning() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let localEnvironmentModelText = try Self.appSourceText(named: "WorkspaceModelLocalEnvironment.swift")
        let projectModelText = try Self.appSourceText(named: "WorkspaceModelProjects.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceShellToolCallPlanner.swift")

        XCTAssertTrue(plannerText.contains("enum WorkspaceShellToolCallPlanner"), "Local action shell tool-call planning should live in a focused planner.")
        XCTAssertTrue(plannerText.contains("static func localEnvironmentAction"), "Local environment action tool calls should be directly testable.")
        XCTAssertTrue(plannerText.contains("static func projectExtensionInstall"), "Extension install tool calls should be directly testable.")
        XCTAssertTrue(plannerText.contains("static func projectExtensionUpdate"), "Extension update tool calls should be directly testable.")
        XCTAssertTrue(plannerText.contains("ToolDefinition.shellRun.name"), "The planner should own the canonical shell tool name.")
        XCTAssertTrue(plannerText.contains("ToolArguments.json(arguments)"), "The planner should own shell argument JSON construction.")
        XCTAssertTrue(localEnvironmentModelText.contains("WorkspaceShellToolCallPlanner.localEnvironmentAction"), "WorkspaceModelLocalEnvironment should delegate local action shell call construction.")
        XCTAssertTrue(projectModelText.contains("WorkspaceShellToolCallPlanner.projectExtensionInstall"), "WorkspaceModelProjects should delegate extension install shell call construction.")
        XCTAssertTrue(projectModelText.contains("WorkspaceShellToolCallPlanner.projectExtensionUpdate"), "WorkspaceModelProjects should delegate extension update shell call construction.")
        XCTAssertFalse(modelText.contains("arguments[\"environment\"] = environment"), "WorkspaceModel should not assemble local action environment arguments inline.")
        XCTAssertFalse(modelText.contains("arguments[\"timeoutSeconds\"] = timeoutSeconds"), "WorkspaceModel should not assemble local action timeout arguments inline.")
        XCTAssertFalse(modelText.contains("WorkspaceShellToolCallPlanner.localEnvironmentAction"), "WorkspaceModel.swift should not own local action shell call execution.")
        XCTAssertFalse(modelText.contains("WorkspaceShellToolCallPlanner.projectExtensionInstall"), "WorkspaceModel.swift should not own extension install shell call execution.")
        XCTAssertFalse(modelText.contains("WorkspaceShellToolCallPlanner.projectExtensionUpdate"), "WorkspaceModel.swift should not own extension update shell call execution.")
        XCTAssertFalse(modelText.contains("let command = manifest.installCommand"), "WorkspaceModel should not parse extension install commands inline.")
        XCTAssertFalse(modelText.contains("let command = manifest.updateCommand"), "WorkspaceModel should not parse extension update commands inline.")
    }


    func testWorkspaceModelDelegatesToolExecutionOverrideCombining() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let builderText = try Self.appSourceText(named: "WorkspaceAgentRunContextBuilder.swift")
        let combinerText = try Self.appSourceText(named: "WorkspaceToolExecutionOverrideCombiner.swift")

        XCTAssertTrue(combinerText.contains("struct WorkspaceToolExecutionOverrideCombiner"), "Tool override composition should live in a focused helper.")
        XCTAssertTrue(combinerText.contains("static func combine"), "Tool override composition should expose a directly testable combine function.")
        XCTAssertTrue(combinerText.contains("activity?(call, workspaceRoot)"), "Activity tool override should keep first dispatch priority.")
        XCTAssertTrue(combinerText.contains("remoteProject?(call, workspaceRoot)"), "Remote-project override should stay before local browser/computer/memory/MCP overrides.")
        XCTAssertTrue(combinerText.contains("mcp?(call, workspaceRoot)"), "MCP override should keep final fallback priority.")
        XCTAssertTrue(builderText.contains("WorkspaceToolExecutionOverrideCombiner.combine"), "Agent run context builder should delegate override composition.")
        XCTAssertFalse(modelText.contains("WorkspaceToolExecutionOverrideCombiner.combine"), "WorkspaceModel should not compose per-run overrides directly.")
        XCTAssertFalse(modelText.contains("private func combinedToolExecutionOverride"), "WorkspaceModel should not own override composition.")
        XCTAssertFalse(modelText.contains("if let result = await activity?(call, workspaceRoot)"), "WorkspaceModel should not inline override precedence.")
        XCTAssertFalse(modelText.contains("if let result = await plan?(call, workspaceRoot)"), "WorkspaceModel should not inline legacy plan override precedence.")
    }
}
