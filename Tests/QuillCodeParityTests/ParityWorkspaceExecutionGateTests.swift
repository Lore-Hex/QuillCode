import XCTest

final class ParityWorkspaceExecutionGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesComposerCancellationPlanning() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceComposerCancellationPlanner.swift")

        XCTAssertTrue(plannerText.contains("struct WorkspaceComposerCancellationPlanner"), "Composer cancellation mutation should live in a focused planner.")
        XCTAssertTrue(plannerText.contains("static func applyCancelledSend"), "Cancelled-send thread mutation should be directly testable.")
        XCTAssertTrue(plannerText.contains("static let stoppedSummary"), "Cancelled-send copy should be shared through the planner.")
        XCTAssertTrue(modelText.contains("WorkspaceComposerCancellationPlanner.applyCancelledSend"), "WorkspaceModel should delegate cancelled-send transcript mutation.")
        XCTAssertFalse(modelText.contains(#""Stopped by user""#), "WorkspaceModel should not own cancelled-send copy.")
        XCTAssertFalse(modelText.contains(#"{"ok":false,"error":"Stopped by user"}"#), "WorkspaceModel should not own cancelled-send result payload copy.")
    }

    func testWorkspaceModelDelegatesComposerSubmissionPlanning() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceComposerSubmissionPlanner.swift")

        XCTAssertTrue(
            plannerText.contains("struct WorkspaceComposerSubmissionPlanner"),
            "Composer submission planning should live in a focused pure planner."
        )
        XCTAssertTrue(
            modelText.contains("WorkspaceComposerSubmissionPlanner.plan"),
            "WorkspaceModel should delegate prompt trimming and slash-command classification."
        )
        XCTAssertFalse(
            modelText.contains("composer.draft.trimmingCharacters"),
            "WorkspaceModel should not own raw composer prompt normalization."
        )
        XCTAssertFalse(
            modelText.contains("SlashCommandParser.parse(prompt)"),
            "WorkspaceModel should not classify slash commands inline."
        )
    }

    func testWorkspaceModelDelegatesAgentSendSessionExecution() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
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
            modelText.contains("WorkspaceAgentSendSessionFactory("),
            "WorkspaceModel should delegate runner execution setup to the send-session factory."
        )
        XCTAssertTrue(
            modelText.contains("WorkspaceAgentSendTaskCoordinator("),
            "WorkspaceModel should delegate active send task execution to the focused coordinator."
        )
        XCTAssertFalse(
            modelText.contains("WorkspaceAgentSendSession("),
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
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceAgentSendStartPlanner.swift")
        let submitStart = try XCTUnwrap(modelText.range(of: "public func submitComposer"))
        let submitEnd = try XCTUnwrap(modelText.range(of: "private func prepareAgentSendThread"))
        let submitBody = String(modelText[submitStart.lowerBound..<submitEnd.lowerBound])

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
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let submitStart = try XCTUnwrap(modelText.range(of: "public func submitComposer"))
        let prepareStart = try XCTUnwrap(modelText.range(of: "private func prepareAgentSendThread"))
        let prepareEnd = try XCTUnwrap(modelText.range(of: "private func agentSendSessionFactory"))
        let submitBody = String(modelText[submitStart.lowerBound..<prepareStart.lowerBound])
        let prepareBody = String(modelText[prepareStart.lowerBound..<prepareEnd.lowerBound])

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
        let plannerText = try Self.appSourceText(named: "WorkspaceAgentSendProgressPlanner.swift")
        let progressStart = try XCTUnwrap(modelText.range(of: "private func applyAgentProgress"))
        let progressEnd = try XCTUnwrap(modelText.range(of: "public func runReviewAction"))
        let progressBody = String(modelText[progressStart.lowerBound..<progressEnd.lowerBound])

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
    }

    func testWorkspaceModelDelegatesAgentSendTerminalPlanning() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceAgentSendTerminalPlanner.swift")
        let submitStart = try XCTUnwrap(modelText.range(of: "public func submitComposer"))
        let submitEnd = try XCTUnwrap(modelText.range(of: "private func prepareAgentSendThread"))
        let submitBody = String(modelText[submitStart.lowerBound..<submitEnd.lowerBound])

        XCTAssertTrue(
            plannerText.contains("struct WorkspaceAgentSendCompletionPlan"),
            "Successful send completion should have a typed plan."
        )
        XCTAssertTrue(
            plannerText.contains("enum WorkspaceAgentSendTerminalPlanner"),
            "Agent send terminal planning should live in a focused planner."
        )
        XCTAssertTrue(
            modelText.contains("private func finishCompletedSend"),
            "WorkspaceModel should route successful send completion through a named helper."
        )
        XCTAssertTrue(
            modelText.contains("private func finishFailedSend"),
            "WorkspaceModel should route failed send completion through a named helper."
        )
        XCTAssertTrue(
            modelText.contains("private func finishAgentSend"),
            "WorkspaceModel should route typed send outcomes through a named terminal helper."
        )
        XCTAssertTrue(
            submitBody.contains("finishAgentSend(outcome)"),
            "submitComposer should delegate typed send outcome handling."
        )
        XCTAssertTrue(
            modelText.contains("try finishCompletedSend(result)"),
            "The terminal helper should delegate successful send completion."
        )
        XCTAssertTrue(
            modelText.contains("finishFailedSend(error)"),
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

    func testWorkspaceModelDelegatesSlashCommandTranscriptPlanning() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let actionExecutorText = try Self.appSourceText(named: "WorkspaceSlashCommandActionExecutor.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceSlashCommandTranscriptPlanner.swift")
        let appenderText = try Self.appSourceText(named: "WorkspaceLocalCommandTranscriptAppender.swift")
        let environmentPlannerText = try Self.appSourceText(named: "WorkspaceEnvironmentSlashCommandPlanner.swift")
        let dispatchPlannerText = try Self.appSourceText(named: "WorkspaceSlashCommandDispatchPlanner.swift")

        XCTAssertTrue(plannerText.contains("struct WorkspaceLocalCommandTranscript"), "Local command transcript records should live beside the planner.")
        XCTAssertTrue(plannerText.contains("struct WorkspaceSlashCommandTranscriptPlanner"), "Slash command transcript copy should live in a focused planner.")
        XCTAssertTrue(appenderText.contains("enum WorkspaceLocalCommandTranscriptAppender"), "Local command transcript mutation should live in a focused appender.")
        XCTAssertTrue(environmentPlannerText.contains("struct WorkspaceEnvironmentSlashCommandPlanner"), "Local environment slash command planning should live in a focused planner.")
        XCTAssertTrue(environmentPlannerText.contains("WorkspaceSlashCommandTranscriptPlanner.environmentActions"), "Local environment list transcripts should be planned outside WorkspaceModel.")
        XCTAssertTrue(environmentPlannerText.contains("WorkspaceSlashCommandTranscriptPlanner.environmentActionNotFound"), "Local environment missing-action transcripts should be planned outside WorkspaceModel.")
        XCTAssertTrue(dispatchPlannerText.contains("WorkspaceSlashCommandTranscriptPlanner.help"), "Help transcripts should be selected by slash dispatch planning.")
        XCTAssertTrue(dispatchPlannerText.contains("WorkspaceSlashCommandTranscriptPlanner.status"), "Status transcripts should be selected by slash dispatch planning.")
        XCTAssertTrue(dispatchPlannerText.contains("WorkspaceSlashCommandTranscriptPlanner.invalid"), "Invalid-command transcripts should be selected by slash dispatch planning.")
        XCTAssertTrue(dispatchPlannerText.contains("WorkspaceSlashCommandTranscriptPlanner.unknown"), "Unknown-command transcripts should be selected by slash dispatch planning.")
        XCTAssertTrue(appenderText.contains("thread.messages.append(ChatMessage(role: .user"), "The transcript appender should own user-message insertion.")
        XCTAssertTrue(appenderText.contains("thread.messages.append(ChatMessage(role: .assistant"), "The transcript appender should own assistant-message insertion.")
        XCTAssertTrue(modelText.contains("WorkspaceLocalCommandTranscriptAppender.append"), "WorkspaceModel should delegate local command transcript mutation.")
        XCTAssertTrue(modelText.contains("WorkspaceEnvironmentSlashCommandPlanner.plan"), "WorkspaceModel should delegate /env list/run/not-found planning.")
        XCTAssertTrue(plannerText.contains("static func sshProjectAdded"), "SSH success copy should be directly testable.")
        XCTAssertTrue(plannerText.contains("static func workspaceCommandFailed"), "Slash command failure copy should be directly testable.")
        XCTAssertTrue(plannerText.contains("SlashCommandCatalog.helpText()"), "Slash help text should stay catalog-backed.")
        for actionExecutorOwnedCall in [
            "WorkspaceSlashCommandTranscriptPlanner.mode",
            "WorkspaceSlashCommandTranscriptPlanner.model",
            "WorkspaceSlashCommandTranscriptPlanner.renameThread",
            "WorkspaceSlashCommandTranscriptPlanner.renameProject",
            "WorkspaceSlashCommandTranscriptPlanner.sshProjectAdded",
            "WorkspaceSlashCommandTranscriptPlanner.workspaceCommandFailed"
        ] {
            XCTAssertTrue(actionExecutorText.contains(actionExecutorOwnedCall), "Slash action execution should delegate \(actionExecutorOwnedCall).")
            XCTAssertFalse(modelText.contains(actionExecutorOwnedCall), "WorkspaceModel should not directly choose \(actionExecutorOwnedCall).")
        }
        for modelOwnedScheduledCall in [
            "WorkspaceSlashCommandTranscriptPlanner.threadFollowUpScheduled",
            "WorkspaceSlashCommandTranscriptPlanner.workspaceScheduleScheduled"
        ] {
            XCTAssertTrue(modelText.contains(modelOwnedScheduledCall), "WorkspaceModel should keep schedule transcript delegation beside schedule persistence.")
        }
        for dispatchOwnedCall in [
            "WorkspaceSlashCommandTranscriptPlanner.help",
            "WorkspaceSlashCommandTranscriptPlanner.status",
            "WorkspaceSlashCommandTranscriptPlanner.invalid",
            "WorkspaceSlashCommandTranscriptPlanner.unknown"
        ] {
            XCTAssertFalse(modelText.contains(dispatchOwnedCall), "WorkspaceModel should let dispatch planning choose \(dispatchOwnedCall).")
        }
        XCTAssertFalse(modelText.contains("Could not rename this chat. Try /rename New chat title."), "WorkspaceModel should not own thread rename fallback copy.")
        XCTAssertFalse(modelText.contains("Could not rename this project. Try /project rename New project name."), "WorkspaceModel should not own project rename fallback copy.")
        XCTAssertFalse(modelText.contains("Use SSH format user@host:/path or ssh://user@host/path."), "WorkspaceModel should not own SSH fallback copy.")
        XCTAssertFalse(modelText.contains("Scheduled a thread follow-up for"), "WorkspaceModel should not own follow-up success copy.")
        XCTAssertFalse(modelText.contains("Scheduled a workspace check for"), "WorkspaceModel should not own workspace schedule success copy.")
        XCTAssertFalse(modelText.contains("WorkspaceSlashCommandTranscriptPlanner.environmentActions"), "WorkspaceModel should not choose /env list transcripts inline.")
        XCTAssertFalse(modelText.contains("WorkspaceSlashCommandTranscriptPlanner.environmentActionNotFound"), "WorkspaceModel should not choose /env missing-action transcripts inline.")
        XCTAssertFalse(modelText.contains("contextResolver.selectedLocalAction(matching:"), "WorkspaceModel should not own /env action matching.")
        XCTAssertFalse(modelText.contains("Local environment actions:"), "WorkspaceModel should not own /env list copy.")
        XCTAssertFalse(modelText.contains("No local environment action matches"), "WorkspaceModel should not own /env missing-action copy.")
        XCTAssertFalse(modelText.contains("Unknown slash command"), "WorkspaceModel should not own unknown slash command copy.")
        XCTAssertFalse(modelText.contains("thread.title = title"), "WorkspaceModel should not own local command title mutation.")
        XCTAssertFalse(modelText.contains("ChatMessage(role: .user, content: userText)"), "WorkspaceModel should not append local command user messages inline.")
        XCTAssertFalse(modelText.contains("ChatMessage(role: .assistant, content: assistantText)"), "WorkspaceModel should not append local command assistant messages inline.")
        XCTAssertFalse(plannerText.contains("memorySaved("), "Memory save copy should live in the memory command planner.")
        XCTAssertFalse(plannerText.contains("memoryNotSaved("), "Memory save failure copy should live in the memory command planner.")
        XCTAssertFalse(plannerText.contains("memorySavedSummary("), "Memory save event summaries should live in the memory command planner.")
    }

    func testWorkspaceModelDelegatesCommandActionPlanning() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceCommandActionPlanner.swift")
        let executorText = try Self.appSourceText(named: "WorkspaceCommandActionExecutor.swift")
        let planExecutorText = try Self.appSourceText(named: "WorkspaceCommandPlanExecutor.swift")

        XCTAssertTrue(plannerText.contains("enum WorkspaceCommandActionEffect"), "Workspace command action effects should live beside the focused planner.")
        XCTAssertTrue(plannerText.contains("struct WorkspaceCommandActionPlanner"), "Workspace command action routing should live in a focused planner.")
        XCTAssertTrue(plannerText.contains("func effect(for action: WorkspaceCommandAction)"), "Command action routing should be directly testable.")
        XCTAssertTrue(executorText.contains("WorkspaceCommandActionPlanner("), "Command action execution should ask the focused planner for typed effects.")
        XCTAssertTrue(executorText.contains("func runWorkspaceCommandAction("), "Command action execution should live in a focused executor.")
        XCTAssertTrue(executorText.contains("func runWorkspaceCommandActionEffect("), "Typed command action effect execution should live in the focused executor.")
        XCTAssertTrue(planExecutorText.contains("return runWorkspaceCommandAction(action)"), "Workspace command-plan execution should delegate typed actions to the focused action executor.")
        XCTAssertFalse(modelText.contains("WorkspaceCommandActionPlanner("), "WorkspaceModel should not own command action planning setup.")
        XCTAssertFalse(modelText.contains("runWorkspaceCommandAction(action)"), "WorkspaceModel should not own command action dispatch.")
        XCTAssertFalse(modelText.contains("runWorkspaceCommandActionEffect"), "WorkspaceModel should not own typed command action effect execution.")
        XCTAssertFalse(modelText.contains("case .toggleTerminal:"), "WorkspaceModel should not own command action effect switching.")
        XCTAssertFalse(modelText.contains("case .projectNewChat:"), "WorkspaceModel should not inline project command action routing.")
        XCTAssertFalse(modelText.contains("case .projectRename:"), "WorkspaceModel should not inline project rename draft routing.")
        XCTAssertFalse(modelText.contains("case .threadBulkArchive:"), "WorkspaceModel should not inline sidebar bulk command routing.")
        XCTAssertFalse(modelText.contains("setDraft(\"/project rename"), "WorkspaceModel should not build project rename drafts inline.")
        XCTAssertFalse(modelText.contains("setDraft(\"/rename"), "WorkspaceModel should not build thread rename drafts inline.")
    }

    func testWorkspaceModelDelegatesCommandPlanExecution() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let executorText = try Self.appSourceText(named: "WorkspaceCommandPlanExecutor.swift")

        XCTAssertTrue(executorText.contains("public func runWorkspaceCommand("), "Public workspace command execution should live in the focused command-plan executor.")
        XCTAssertTrue(executorText.contains("WorkspaceCommandPlan(commandID: commandID)"), "Command ID parsing should stay beside plan execution.")
        XCTAssertTrue(executorText.contains("func runWorkspaceCommandPlan("), "Parsed command-plan execution should be directly testable.")
        XCTAssertTrue(executorText.contains("switch plan"), "The command-plan switch should live in the focused executor.")
        XCTAssertTrue(executorText.contains("return runWorkspaceCommandAction(action)"), "Typed command actions should still delegate to the action executor.")
        XCTAssertFalse(modelText.contains("WorkspaceCommandPlan(commandID: commandID)"), "WorkspaceModel should not parse command IDs inline.")
        XCTAssertFalse(modelText.contains("case .localEnvironmentAction"), "WorkspaceModel should not own command-plan execution switching.")
        XCTAssertFalse(modelText.contains("case .startMCPServer"), "WorkspaceModel should not own MCP command-plan routing.")
        XCTAssertFalse(modelText.contains("case .runTool"), "WorkspaceModel should not own tool command-plan routing.")
    }

    func testWorkspaceModelDelegatesAgentRunContextAssembly() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let builderText = try Self.appSourceText(named: "WorkspaceAgentRunContextBuilder.swift")
        let factoryText = try Self.appSourceText(named: "WorkspaceAgentSendSessionFactory.swift")
        let memoryExecutorText = try Self.appSourceText(named: "WorkspaceMemoryRememberToolExecutor.swift")

        XCTAssertTrue(factoryText.contains("WorkspaceAgentRunContextBuilder("), "The send-session factory should delegate per-run tool assembly.")
        XCTAssertTrue(modelText.contains("WorkspaceAgentSendSessionFactory("), "WorkspaceModel should delegate per-run session assembly.")
        XCTAssertTrue(builderText.contains("configuredRunner(from runner: AgentRunner)"), "Agent run context builder should own runner configuration.")
        XCTAssertTrue(builderText.contains("ToolDefinition.planUpdate"), "Agent run context builder should attach the plan tool.")
        XCTAssertTrue(builderText.contains("ToolDefinition.browserInspect"), "Agent run context builder should attach the browser tool.")
        XCTAssertTrue(builderText.contains("ToolDefinition.browserOpen"), "Agent run context builder should attach browser navigation.")
        XCTAssertTrue(builderText.contains("WorkspaceBrowserToolExecutor.execute"), "Browser tool execution should stay in the focused browser executor.")
        XCTAssertTrue(builderText.contains("ToolDefinition.computerUseDefinitions"), "Agent run context builder should attach Computer Use tools only when available.")
        XCTAssertTrue(builderText.contains("WorkspaceMemoryRememberToolExecutor.executionOverride"), "Agent run context builder should delegate memory tool execution.")
        XCTAssertTrue(memoryExecutorText.contains("didSaveMemory(in thread: ChatThread)"), "Memory save detection should live beside memory tool execution.")
        XCTAssertFalse(modelText.contains("WorkspaceAgentRunContextBuilder("), "WorkspaceModel should not construct the run-context builder inline.")
        XCTAssertFalse(modelText.contains("activeRunner.additionalToolDefinitions"), "WorkspaceModel should not assemble per-run additional tool definitions inline.")
        XCTAssertFalse(modelText.contains("private func planToolExecutionOverride"), "WorkspaceModel should not own plan tool override assembly.")
        XCTAssertFalse(modelText.contains("private func browserToolExecutionOverride"), "WorkspaceModel should not own browser tool override assembly.")
        XCTAssertFalse(modelText.contains("private func memoryToolExecutionOverride"), "WorkspaceModel should not own memory tool override assembly.")
        XCTAssertFalse(modelText.contains("private nonisolated static func didSaveMemory"), "WorkspaceModel should not own memory-save event parsing.")
    }

    func testWorkspaceModelDelegatesAgentSendSession() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let factoryText = try Self.appSourceText(named: "WorkspaceAgentSendSessionFactory.swift")
        let sessionText = try Self.appSourceText(named: "WorkspaceAgentSendSession.swift")

        XCTAssertTrue(sessionText.contains("struct WorkspaceAgentSendSession"), "Agent send lifecycle should live in a focused session.")
        XCTAssertTrue(sessionText.contains("func run("), "Agent send lifecycle should be directly testable.")
        XCTAssertTrue(sessionText.contains("runner.send("), "The session should own the runner send call.")
        XCTAssertTrue(sessionText.contains("WorkspaceMemoryRememberToolExecutor.didSaveMemory"), "The session should report whether the run saved memory.")
        XCTAssertTrue(factoryText.contains("WorkspaceAgentSendSession("), "The factory should own agent send session construction.")
        XCTAssertTrue(modelText.contains("WorkspaceAgentSendSessionFactory("), "WorkspaceModel should delegate agent send execution setup.")
        XCTAssertFalse(modelText.contains("WorkspaceAgentSendSession("), "WorkspaceModel should not construct agent send sessions inline.")
        XCTAssertFalse(modelText.contains("activeRunner.send("), "WorkspaceModel should not own the low-level send call.")
        XCTAssertFalse(modelText.contains("WorkspaceMemoryRememberToolExecutor.didSaveMemory(in: thread)"), "WorkspaceModel should not inspect memory events after each send.")
    }

    func testWorkspaceModelDelegatesToolEventRecording() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let recorderText = try Self.appSourceText(named: "WorkspaceToolEventRecorder.swift")

        XCTAssertTrue(recorderText.contains("struct WorkspaceToolEventRecorder"), "Tool audit event construction should live in a focused recorder.")
        XCTAssertTrue(recorderText.contains("static func events"), "Tool event construction should be directly testable.")
        XCTAssertTrue(recorderText.contains("static func append"), "Thread mutation should be a thin append helper.")
        XCTAssertTrue(recorderText.contains("call.redactedForTranscript()"), "Tool call redaction should live beside queued-event construction.")
        XCTAssertTrue(recorderText.contains("result.ok ? .toolCompleted : .toolFailed"), "Completion/failure classification should live beside tool event construction.")
        XCTAssertTrue(modelText.contains("WorkspaceToolEventRecorder.append"), "WorkspaceModel should delegate tool audit event recording.")
        XCTAssertFalse(modelText.contains("call.redactedForTranscript()"), "WorkspaceModel should not own tool call redaction for transcript events.")
        XCTAssertFalse(modelText.contains("let resultJSON ="), "WorkspaceModel should not own tool result JSON payload construction.")
        XCTAssertFalse(modelText.contains("summary: \"\\(call.name) queued\""), "WorkspaceModel should not construct queued tool summaries directly.")
        XCTAssertFalse(modelText.contains("summary: \"\\(call.name) running\""), "WorkspaceModel should not construct running tool summaries directly.")
    }

    func testWorkspaceModelDelegatesToolCallExecutionRouting() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let executorText = try Self.appSourceText(named: "WorkspaceToolCallExecutor.swift")

        XCTAssertTrue(executorText.contains("struct WorkspaceToolCallExecutor"), "Tool-call routing should live in a focused executor.")
        XCTAssertTrue(executorText.contains("WorkspaceBrowserToolExecutor.execute"), "The executor should own browser tool routing.")
        XCTAssertTrue(executorText.contains("PlanUpdateToolExecutor.execute"), "The executor should own plan update routing.")
        XCTAssertTrue(executorText.contains("WorkspaceRemoteProjectToolExecutor.execute"), "The executor should own remote project routing.")
        XCTAssertTrue(executorText.contains("ToolDefinition.applyPatch.name"), "The executor should own apply-patch follow-up routing.")
        XCTAssertTrue(modelText.contains("workspaceToolCallExecutor(router:"), "WorkspaceModel should delegate tool execution routing.")
        XCTAssertFalse(modelText.contains("call.name == ToolDefinition.browserInspect.name"), "WorkspaceModel should not branch on browser inspect tool execution.")
        XCTAssertFalse(modelText.contains("call.name == ToolDefinition.browserOpen.name"), "WorkspaceModel should not branch on browser open tool execution.")
        XCTAssertFalse(modelText.contains("call.name == ToolDefinition.planUpdate.name"), "WorkspaceModel should not branch on plan update tool execution.")
        XCTAssertFalse(modelText.contains("private func appendReviewDiffAfterPatchIfNeeded"), "WorkspaceModel should not own apply-patch review diff follow-up routing.")
        XCTAssertFalse(modelText.contains("private func executeReviewGitToolCall"), "WorkspaceModel should not own parallel review git routing.")
    }

    func testWorkspaceModelDelegatesToolRunPreparation() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let preparerText = try Self.appSourceText(named: "WorkspaceToolRunPreparer.swift")
        let runToolCallStart = try XCTUnwrap(modelText.range(of: "public func runToolCall"))
        let runToolCallEnd = try XCTUnwrap(modelText.range(
            of: "public func runTerminalCommand",
            range: runToolCallStart.upperBound..<modelText.endIndex
        ))
        let runToolCallBody = String(modelText[runToolCallStart.lowerBound..<runToolCallEnd.lowerBound])

        XCTAssertTrue(preparerText.contains("enum WorkspaceToolRunPreparer"), "Tool-run context preparation should live in a focused helper.")
        XCTAssertTrue(preparerText.contains("static func effectiveProjectID"), "Effective tool-run project selection should be directly testable.")
        XCTAssertTrue(preparerText.contains("static func syncThreadContext"), "Tool-run thread context sync should be directly testable.")
        XCTAssertTrue(runToolCallBody.contains("WorkspaceToolRunPreparer.effectiveProjectID"), "WorkspaceModel should delegate tool-run project selection.")
        XCTAssertTrue(runToolCallBody.contains("WorkspaceToolRunPreparer.syncThreadContext"), "WorkspaceModel should delegate tool-run thread context sync.")
        XCTAssertFalse(runToolCallBody.contains("workspaceThreadContext("), "runToolCall should not rebuild thread context inline.")
        XCTAssertFalse(runToolCallBody.contains("thread.instructions ="), "runToolCall should not assign instruction snapshots inline.")
        XCTAssertFalse(runToolCallBody.contains("thread.memories ="), "runToolCall should not assign memory snapshots inline.")
    }

    func testWorkspaceModelDelegatesShellToolCallPlanning() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceShellToolCallPlanner.swift")

        XCTAssertTrue(plannerText.contains("enum WorkspaceShellToolCallPlanner"), "Local action shell tool-call planning should live in a focused planner.")
        XCTAssertTrue(plannerText.contains("static func localEnvironmentAction"), "Local environment action tool calls should be directly testable.")
        XCTAssertTrue(plannerText.contains("static func projectExtensionUpdate"), "Extension update tool calls should be directly testable.")
        XCTAssertTrue(plannerText.contains("ToolDefinition.shellRun.name"), "The planner should own the canonical shell tool name.")
        XCTAssertTrue(plannerText.contains("ToolArguments.json(arguments)"), "The planner should own shell argument JSON construction.")
        XCTAssertTrue(modelText.contains("WorkspaceShellToolCallPlanner.localEnvironmentAction"), "WorkspaceModel should delegate local action shell call construction.")
        XCTAssertTrue(modelText.contains("WorkspaceShellToolCallPlanner.projectExtensionUpdate"), "WorkspaceModel should delegate extension update shell call construction.")
        XCTAssertFalse(modelText.contains("arguments[\"environment\"] = environment"), "WorkspaceModel should not assemble local action environment arguments inline.")
        XCTAssertFalse(modelText.contains("arguments[\"timeoutSeconds\"] = timeoutSeconds"), "WorkspaceModel should not assemble local action timeout arguments inline.")
        XCTAssertFalse(modelText.contains("let command = manifest.updateCommand"), "WorkspaceModel should not parse extension update commands inline.")
    }

    func testWorkspaceComposerIntegrationTestsOwnModelComposerFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let composerIntegrationTests = try Self.appTestSourceText(named: "WorkspaceComposerIntegrationTests.swift")

        XCTAssertTrue(composerIntegrationTests.contains("testSubmitComposerRunsToolAndBuildsToolCard"), "Composer tool-card integration should live in focused composer integration tests.")
        XCTAssertTrue(composerIntegrationTests.contains("testSubmitComposerSurfacesToolArtifacts"), "Composer artifact integration should live in focused composer integration tests.")
        XCTAssertTrue(composerIntegrationTests.contains("testSubmitComposerDispatchesComputerUseToolThroughBackend"), "Composer Computer Use integration should live in focused composer integration tests.")
        XCTAssertTrue(composerIntegrationTests.contains("testSubmitComposerStreamsQueuedToolBeforeCompletion"), "Composer queued-tool streaming integration should live in focused composer integration tests.")
        XCTAssertTrue(composerIntegrationTests.contains("testCancellingComposerRunStopsStateAndRecordsNotice"), "Composer cancellation integration should live in focused composer integration tests.")
        XCTAssertTrue(composerIntegrationTests.contains("testCompletedComposerRunDoesNotStealSelectionAfterUserSwitchesThreads"), "Composer selection-race integration should live in focused composer integration tests.")
        XCTAssertFalse(modelTests.contains("testSubmitComposerRunsToolAndBuildsToolCard"), "WorkspaceModelTests should not own composer tool-card integration flows.")
        XCTAssertFalse(modelTests.contains("testSubmitComposerSurfacesToolArtifacts"), "WorkspaceModelTests should not own composer artifact integration flows.")
        XCTAssertFalse(modelTests.contains("testSubmitComposerDispatchesComputerUseToolThroughBackend"), "WorkspaceModelTests should not own composer Computer Use integration flows.")
        XCTAssertFalse(modelTests.contains("testSubmitComposerStreamsQueuedToolBeforeCompletion"), "WorkspaceModelTests should not own composer queued-tool streaming integration flows.")
        XCTAssertFalse(modelTests.contains("testCancellingComposerRunStopsStateAndRecordsNotice"), "WorkspaceModelTests should not own composer cancellation integration flows.")
        XCTAssertFalse(modelTests.contains("testCompletedComposerRunDoesNotStealSelectionAfterUserSwitchesThreads"), "WorkspaceModelTests should not own composer selection-race integration flows.")
    }

    func testWorkspaceModelDelegatesSlashCommandDispatchPlanning() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceSlashCommandDispatchPlanner.swift")
        let actionExecutorText = try Self.appSourceText(named: "WorkspaceSlashCommandActionExecutor.swift")
        let plannerTests = try Self.appTestSourceText(named: "WorkspaceSlashCommandDispatchPlannerTests.swift")

        XCTAssertTrue(plannerText.contains("enum WorkspaceSlashCommandDispatchAction"), "Slash dispatch actions should be typed values outside WorkspaceModel.")
        XCTAssertTrue(plannerText.contains("struct WorkspaceSlashCommandDispatchPlanner"), "Slash dispatch planning should live outside WorkspaceModel.")
        XCTAssertTrue(plannerText.contains("static func action("), "Slash dispatch mapping should be directly testable.")
        XCTAssertTrue(plannerText.contains("case .help:"), "Raw parsed slash-command cases should live in the planner.")
        XCTAssertTrue(plannerText.contains("case .environmentAction(let query):"), "Environment slash routing should live in the planner.")
        XCTAssertTrue(actionExecutorText.contains("extension QuillCodeWorkspaceModel"), "Slash action execution should live in a focused model extension.")
        XCTAssertTrue(actionExecutorText.contains("func runSlashCommandDispatchAction"), "Typed slash action application should live outside the main model file.")
        XCTAssertTrue(actionExecutorText.contains("switch action"), "The slash action executor should own the typed action switch.")
        XCTAssertTrue(modelText.contains("WorkspaceSlashCommandDispatchPlanner.action("), "WorkspaceModel should consume the slash dispatch planner.")
        XCTAssertTrue(modelText.contains("runSlashCommandDispatchAction(action, workspaceRoot: workspaceRoot)"), "WorkspaceModel should delegate typed slash action application.")
        XCTAssertTrue(plannerTests.contains("testExternalCommandFamiliesMapToTypedActions"), "Slash dispatch families should have focused planner coverage.")
        XCTAssertFalse(modelText.contains("switch command {\n        case .help:"), "WorkspaceModel should not switch directly over parsed slash commands.")
        XCTAssertFalse(modelText.contains("switch action {"), "WorkspaceModel should not own typed slash action application.")
        XCTAssertFalse(modelText.contains("case .appendTranscript"), "WorkspaceModel should not own typed slash transcript actions.")
        XCTAssertFalse(modelText.contains("case .setMode"), "WorkspaceModel should not own typed slash mode actions.")
        XCTAssertFalse(modelText.contains("WorkspaceSlashCommandTranscriptPlanner.workspaceCommandFailed"), "WorkspaceModel should not own slash workspace-command failure transcripts.")
        XCTAssertFalse(modelText.contains("case .unknown(let name):"), "WorkspaceModel should not own unknown slash-command transcripts.")
        XCTAssertFalse(modelText.contains("case .invalid(let message):"), "WorkspaceModel should not own invalid slash-command transcripts.")
    }

    func testWorkspaceModelDelegatesToolExecutionOverrideCombining() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let builderText = try Self.appSourceText(named: "WorkspaceAgentRunContextBuilder.swift")
        let combinerText = try Self.appSourceText(named: "WorkspaceToolExecutionOverrideCombiner.swift")

        XCTAssertTrue(combinerText.contains("struct WorkspaceToolExecutionOverrideCombiner"), "Tool override composition should live in a focused helper.")
        XCTAssertTrue(combinerText.contains("static func combine"), "Tool override composition should expose a directly testable combine function.")
        XCTAssertTrue(combinerText.contains("plan?(call, workspaceRoot)"), "Plan override should keep first dispatch priority.")
        XCTAssertTrue(combinerText.contains("remoteProject?(call, workspaceRoot)"), "Remote-project override should stay before local browser/computer/memory/MCP overrides.")
        XCTAssertTrue(combinerText.contains("mcp?(call, workspaceRoot)"), "MCP override should keep final fallback priority.")
        XCTAssertTrue(builderText.contains("WorkspaceToolExecutionOverrideCombiner.combine"), "Agent run context builder should delegate override composition.")
        XCTAssertFalse(modelText.contains("WorkspaceToolExecutionOverrideCombiner.combine"), "WorkspaceModel should not compose per-run overrides directly.")
        XCTAssertFalse(modelText.contains("private func combinedToolExecutionOverride"), "WorkspaceModel should not own override composition.")
        XCTAssertFalse(modelText.contains("if let result = await plan?(call, workspaceRoot)"), "WorkspaceModel should not inline override precedence.")
    }
}
