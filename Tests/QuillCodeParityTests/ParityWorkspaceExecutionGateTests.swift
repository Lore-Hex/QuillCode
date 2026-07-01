import XCTest

final class ParityWorkspaceExecutionGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesComposerCancellationPlanning() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let composerText = try Self.appSourceText(named: "WorkspaceModelComposer.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceComposerCancellationPlanner.swift")

        XCTAssertTrue(plannerText.contains("struct WorkspaceComposerCancellationPlanner"), "Composer cancellation mutation should live in a focused planner.")
        XCTAssertTrue(plannerText.contains("static func applyCancelledSend"), "Cancelled-send thread mutation should be directly testable.")
        XCTAssertTrue(plannerText.contains("static let stoppedSummary"), "Cancelled-send copy should be shared through the planner.")
        XCTAssertTrue(composerText.contains("WorkspaceComposerCancellationPlanner.applyCancelledSend"), "WorkspaceModel composer APIs should delegate cancelled-send transcript mutation.")
        XCTAssertFalse(modelText.contains("WorkspaceComposerCancellationPlanner.applyCancelledSend"), "WorkspaceModel.swift should not own cancelled-send transcript mutation.")
        XCTAssertFalse(modelText.contains(#""Stopped by user""#), "WorkspaceModel should not own cancelled-send copy.")
        XCTAssertFalse(modelText.contains(#"{"ok":false,"error":"Stopped by user"}"#), "WorkspaceModel should not own cancelled-send result payload copy.")
    }

    func testWorkspaceModelDelegatesComposerSubmissionPlanning() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let composerText = try Self.appSourceText(named: "WorkspaceModelComposer.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceComposerSubmissionPlanner.swift")

        XCTAssertTrue(
            plannerText.contains("struct WorkspaceComposerSubmissionPlanner"),
            "Composer submission planning should live in a focused pure planner."
        )
        XCTAssertTrue(
            composerText.contains("WorkspaceComposerSubmissionPlanner.plan"),
            "WorkspaceModel composer APIs should delegate prompt trimming and slash-command classification."
        )
        XCTAssertFalse(
            composerText.contains("composer.draft.trimmingCharacters"),
            "WorkspaceModel composer APIs should not own raw composer prompt normalization."
        )
        XCTAssertFalse(
            composerText.contains("SlashCommandParser.parse(prompt)"),
            "WorkspaceModel should not classify slash commands inline."
        )
        XCTAssertFalse(modelText.contains("public func submitComposer"), "WorkspaceModel.swift should not own composer submission APIs.")
    }

    func testWorkspaceModelDelegatesAgentSendSessionExecution() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let composerText = try Self.appSourceText(named: "WorkspaceModelComposer.swift")
        let factoryText = try Self.appSourceText(named: "WorkspaceAgentSendSessionFactory.swift")
        let sessionText = try Self.appSourceText(named: "WorkspaceAgentSendSession.swift")
        let coordinatorText = try Self.appSourceText(named: "WorkspaceAgentSendTaskCoordinator.swift")
        let coordinatorTests = try Self.appTestSourceText(named: "WorkspaceAgentSendTaskCoordinatorTests.swift")

        XCTAssertTrue(
            sessionText.contains("struct WorkspaceAgentSendSession"),
            "Agent send execution should live in a focused session object."
        )
        XCTAssertTrue(
            coordinatorText.contains("enum WorkspaceAgentSendTaskOutcome"),
            "Agent send task terminal states should have a typed outcome."
        )
        XCTAssertTrue(
            coordinatorText.contains("struct WorkspaceAgentSendTaskCoordinator"),
            "Agent send task execution and error classification should live in a focused coordinator."
        )
        XCTAssertTrue(
            coordinatorText.contains("case completed"),
            "The task coordinator should preserve successful completion as an explicit outcome."
        )
        XCTAssertTrue(
            coordinatorText.contains("case cancelled"),
            "The task coordinator should preserve cancellation as an explicit outcome."
        )
        XCTAssertTrue(
            coordinatorText.contains("case failed"),
            "The task coordinator should preserve runtime failures as an explicit outcome."
        )
        XCTAssertTrue(
            factoryText.contains("WorkspaceAgentSendSession("),
            "Agent send session construction should live in the send-session factory."
        )
        XCTAssertTrue(
            coordinatorTests.contains("testRunReturnsCompletedOutcome"),
            "Focused coordinator tests should cover successful task completion."
        )
        XCTAssertTrue(
            coordinatorTests.contains("testRunConvertsCancellationToStoppedOutcome"),
            "Focused coordinator tests should cover cancellation classification."
        )
        XCTAssertTrue(
            coordinatorTests.contains("testRunConvertsRuntimeErrorToFailedOutcome"),
            "Focused coordinator tests should cover runtime failure classification."
        )
        XCTAssertTrue(
            composerText.contains("WorkspaceAgentSendSessionFactory("),
            "WorkspaceModel composer APIs should delegate runner execution setup to the send-session factory."
        )
        XCTAssertTrue(
            composerText.contains("WorkspaceAgentSendTaskCoordinator("),
            "WorkspaceModel composer APIs should delegate active send task execution to the focused coordinator."
        )
        XCTAssertFalse(
            composerText.contains("WorkspaceAgentSendSession("),
            "WorkspaceModel should not construct agent send sessions inline."
        )
        XCTAssertFalse(
            modelText.contains("activeRunner.send("),
            "WorkspaceModel should not call the runner directly from submitComposer."
        )
        XCTAssertFalse(
            modelText.contains("WorkspaceMemoryRememberToolExecutor.didSaveMemory(in: thread)"),
            "WorkspaceModel should not inspect completed run memory events inline."
        )
    }

    func testWorkspaceModelDelegatesAgentSendStartPlanning() throws {
        let composerText = try Self.appSourceText(named: "WorkspaceModelComposer.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceAgentSendStartPlanner.swift")
        let submitStart = try XCTUnwrap(composerText.range(of: "public func submitComposer"))
        let submitEnd = try XCTUnwrap(composerText.range(of: "private func prepareAgentSendThread"))
        let submitBody = String(composerText[submitStart.lowerBound..<submitEnd.lowerBound])

        XCTAssertTrue(
            plannerText.contains("struct WorkspaceAgentSendStartPlan"),
            "Agent send start should have a typed plan."
        )
        XCTAssertTrue(
            plannerText.contains("enum WorkspaceAgentSendStartPlanner"),
            "Agent send start planning should live in a focused planner."
        )
        XCTAssertTrue(
            submitBody.contains("WorkspaceAgentSendStartPlanner.started"),
            "submitComposer should delegate send-start planning."
        )
        XCTAssertFalse(
            submitBody.contains("WorkspaceComposerSendLifecycle.started"),
            "submitComposer should not choose started lifecycle state inline."
        )
    }

    func testWorkspaceModelDelegatesAgentSendThreadPreparation() throws {
        let composerText = try Self.appSourceText(named: "WorkspaceModelComposer.swift")
        let preparerText = try Self.appSourceText(named: "WorkspaceThreadContextPreparer.swift")
        let submitStart = try XCTUnwrap(composerText.range(of: "public func submitComposer"))
        let prepareStart = try XCTUnwrap(composerText.range(of: "private func prepareAgentSendThread"))
        let prepareEnd = try XCTUnwrap(composerText.range(of: "private func agentSendSessionFactory"))
        let submitBody = String(composerText[submitStart.lowerBound..<prepareStart.lowerBound])
        let prepareBody = String(composerText[prepareStart.lowerBound..<prepareEnd.lowerBound])

        XCTAssertTrue(
            submitBody.contains("prepareAgentSendThread()"),
            "submitComposer should delegate thread creation and context sync to a named preparation boundary."
        )
        XCTAssertTrue(
            prepareBody.contains("_ = newChat()"),
            "The preparation boundary should own first-thread creation."
        )
        XCTAssertTrue(
            prepareBody.contains("syncThreadContext(into: &thread)"),
            "The preparation boundary should own agent-send context sync."
        )
        XCTAssertTrue(
            preparerText.contains("enum WorkspaceThreadContextPreparer"),
            "Shared thread context preparation should live in a focused helper."
        )
        XCTAssertTrue(
            preparerText.contains("WorkspaceProjectContextRefresher.syncThreadContext"),
            "The shared preparer should own project instruction and memory synchronization."
        )
        XCTAssertTrue(
            composerText.contains("WorkspaceThreadContextPreparer.syncThreadContext"),
            "Agent send preparation should use the shared context preparer."
        )
        XCTAssertFalse(
            composerText.contains("WorkspaceProjectContextRefresher.syncThreadContext"),
            "Agent send preparation should not sync project context directly."
        )
        XCTAssertFalse(
            submitBody.contains("_ = newChat()"),
            "submitComposer should not create first threads inline."
        )
        XCTAssertFalse(
            submitBody.contains("syncThreadContext(into:"),
            "submitComposer should not sync thread context inline."
        )
    }

    func testWorkspaceModelDelegatesAgentSendProgressPlanning() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let composerText = try Self.appSourceText(named: "WorkspaceModelComposer.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceAgentSendProgressPlanner.swift")
        let progressStart = try XCTUnwrap(composerText.range(of: "private func applyAgentProgress"))
        let progressEnd = try XCTUnwrap(composerText.range(of: "private func executeBrowserToolForAgent"))
        let progressBody = String(composerText[progressStart.lowerBound..<progressEnd.lowerBound])

        XCTAssertTrue(
            plannerText.contains("struct WorkspaceAgentSendProgressPlan"),
            "Agent progress updates should have a typed plan."
        )
        XCTAssertTrue(
            plannerText.contains("enum WorkspaceAgentSendProgressPlanner"),
            "Agent progress planning should live in a focused planner."
        )
        XCTAssertTrue(
            progressBody.contains("WorkspaceAgentSendProgressPlanner.progress"),
            "WorkspaceModel should delegate agent progress UI-state planning."
        )
        XCTAssertFalse(
            progressBody.contains("WorkspaceAgentStatusBuilder.status"),
            "WorkspaceModel should not choose progress top-bar copy inline."
        )
        XCTAssertFalse(
            progressBody.contains("composer.isSending = true"),
            "WorkspaceModel should not choose progress composer state inline."
        )
        XCTAssertFalse(
            progressBody.contains("lastError = nil"),
            "WorkspaceModel should not clear progress errors inline."
        )
        XCTAssertFalse(modelText.contains("private func applyAgentProgress"), "WorkspaceModel.swift should not own agent-send progress APIs.")
    }

    func testWorkspaceModelDelegatesAgentSendTerminalPlanning() throws {
        let composerText = try Self.appSourceText(named: "WorkspaceModelComposer.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceAgentSendTerminalPlanner.swift")
        let submitStart = try XCTUnwrap(composerText.range(of: "public func submitComposer"))
        let submitEnd = try XCTUnwrap(composerText.range(of: "private func prepareAgentSendThread"))
        let submitBody = String(composerText[submitStart.lowerBound..<submitEnd.lowerBound])

        XCTAssertTrue(
            plannerText.contains("struct WorkspaceAgentSendCompletionPlan"),
            "Successful send completion should have a typed plan."
        )
        XCTAssertTrue(
            plannerText.contains("enum WorkspaceAgentSendTerminalPlanner"),
            "Agent send terminal planning should live in a focused planner."
        )
        XCTAssertTrue(
            composerText.contains("private func finishCompletedSend"),
            "WorkspaceModel composer APIs should route successful send completion through a named helper."
        )
        XCTAssertTrue(
            composerText.contains("private func finishFailedSend"),
            "WorkspaceModel composer APIs should route failed send completion through a named helper."
        )
        XCTAssertTrue(
            composerText.contains("private func finishAgentSend"),
            "WorkspaceModel composer APIs should route typed send outcomes through a named terminal helper."
        )
        XCTAssertTrue(
            submitBody.contains("finishAgentSend(outcome, runThreadID:"),
            "submitComposer should delegate typed send outcome handling."
        )
        XCTAssertTrue(
            composerText.contains("try finishCompletedSend(result)"),
            "The terminal helper should delegate successful send completion."
        )
        XCTAssertTrue(
            composerText.contains("finishFailedSend(error)"),
            "The terminal helper should delegate failed send completion."
        )
        XCTAssertFalse(
            submitBody.contains("catch is CancellationError"),
            "submitComposer should not classify send cancellation inline."
        )
        XCTAssertFalse(
            submitBody.contains("catch {"),
            "submitComposer should not classify send failures inline."
        )
        XCTAssertFalse(
            submitBody.contains("result.savedMemory"),
            "submitComposer should not branch on memory-save details inline."
        )
        XCTAssertFalse(
            submitBody.contains("refreshThreadMemoryContext"),
            "submitComposer should not refresh memory context inline."
        )
        XCTAssertFalse(
            submitBody.contains("threadPersistence.saveOrThrow"),
            "submitComposer should not own final persistence inline."
        )
        XCTAssertFalse(
            submitBody.contains("WorkspaceComposerSendLifecycle.completed"),
            "submitComposer should not choose completion lifecycle state inline."
        )
        XCTAssertFalse(
            submitBody.contains("WorkspaceComposerSendLifecycle.failed"),
            "submitComposer should not choose failed lifecycle state inline."
        )
    }

}
