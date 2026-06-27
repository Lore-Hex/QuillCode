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
            submitBody.contains("finishAgentSend(outcome)"),
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

    func testWorkspaceModelDelegatesSlashCommandTranscriptPlanning() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let composerText = try Self.appSourceText(named: "WorkspaceModelComposer.swift")
        let actionExecutorText = try Self.appSourceText(named: "WorkspaceSlashCommandActionExecutor.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceSlashCommandTranscriptPlanner.swift")
        let appenderText = try Self.appSourceText(named: "WorkspaceLocalCommandTranscriptAppender.swift")
        let environmentPlannerText = try Self.appSourceText(named: "WorkspaceEnvironmentSlashCommandPlanner.swift")
        let localEnvironmentModelText = try Self.appSourceText(named: "WorkspaceModelLocalEnvironment.swift")
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
        XCTAssertTrue(composerText.contains("WorkspaceLocalCommandTranscriptAppender.append"), "WorkspaceModel composer APIs should delegate local command transcript mutation.")
        XCTAssertTrue(localEnvironmentModelText.contains("public func runLocalEnvironmentAction"), "Local environment action execution should live in the focused WorkspaceModelLocalEnvironment extension.")
        XCTAssertTrue(localEnvironmentModelText.contains("func runEnvironmentSlashCommand"), "Local environment slash command dispatch should live in the focused WorkspaceModelLocalEnvironment extension.")
        XCTAssertTrue(localEnvironmentModelText.contains("WorkspaceEnvironmentSlashCommandPlanner.plan"), "WorkspaceModelLocalEnvironment should delegate /env list/run/not-found planning.")
        XCTAssertFalse(modelText.contains("public func runLocalEnvironmentAction"), "WorkspaceModel.swift should not own local environment action execution.")
        XCTAssertFalse(modelText.contains("func runEnvironmentSlashCommand"), "WorkspaceModel.swift should not own local environment slash command dispatch.")
        XCTAssertFalse(modelText.contains("WorkspaceLocalCommandTranscriptAppender.append"), "WorkspaceModel.swift should not own local command transcript mutation.")
        XCTAssertFalse(modelText.contains("WorkspaceEnvironmentSlashCommandPlanner.plan"), "WorkspaceModel.swift should not directly choose /env list/run/not-found planning.")
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
            XCTAssertTrue(composerText.contains(modelOwnedScheduledCall), "WorkspaceModel composer APIs should keep schedule transcript delegation beside schedule persistence.")
            XCTAssertFalse(modelText.contains(modelOwnedScheduledCall), "WorkspaceModel.swift should not own schedule transcript delegation.")
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
        let composerText = try Self.appSourceText(named: "WorkspaceModelComposer.swift")
        let builderText = try Self.appSourceText(named: "WorkspaceAgentRunContextBuilder.swift")
        let factoryText = try Self.appSourceText(named: "WorkspaceAgentSendSessionFactory.swift")
        let memoryExecutorText = try Self.appSourceText(named: "WorkspaceMemoryRememberToolExecutor.swift")

        XCTAssertTrue(factoryText.contains("WorkspaceAgentRunContextBuilder("), "The send-session factory should delegate per-run tool assembly.")
        XCTAssertTrue(composerText.contains("WorkspaceAgentSendSessionFactory("), "WorkspaceModel composer APIs should delegate per-run session assembly.")
        XCTAssertTrue(builderText.contains("configuredRunner(from runner: AgentRunner)"), "Agent run context builder should own runner configuration.")
        XCTAssertTrue(builderText.contains("ToolDefinition.planUpdate"), "Agent run context builder should attach the plan tool.")
        XCTAssertTrue(builderText.contains("ToolDefinition.handoffUpdate"), "Agent run context builder should attach the handoff summary tool.")
        XCTAssertTrue(builderText.contains("ToolDefinition.browserInspect"), "Agent run context builder should attach the browser tool.")
        XCTAssertTrue(builderText.contains("ToolDefinition.browserOpen"), "Agent run context builder should attach browser navigation.")
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
        let composerText = try Self.appSourceText(named: "WorkspaceModelComposer.swift")
        let factoryText = try Self.appSourceText(named: "WorkspaceAgentSendSessionFactory.swift")
        let sessionText = try Self.appSourceText(named: "WorkspaceAgentSendSession.swift")

        XCTAssertTrue(sessionText.contains("struct WorkspaceAgentSendSession"), "Agent send lifecycle should live in a focused session.")
        XCTAssertTrue(sessionText.contains("func run("), "Agent send lifecycle should be directly testable.")
        XCTAssertTrue(sessionText.contains("runner.send("), "The session should own the runner send call.")
        XCTAssertTrue(sessionText.contains("WorkspaceMemoryRememberToolExecutor.didSaveMemory"), "The session should report whether the run saved memory.")
        XCTAssertTrue(factoryText.contains("WorkspaceAgentSendSession("), "The factory should own agent send session construction.")
        XCTAssertTrue(composerText.contains("WorkspaceAgentSendSessionFactory("), "WorkspaceModel composer APIs should delegate agent send execution setup.")
        XCTAssertFalse(modelText.contains("WorkspaceAgentSendSession("), "WorkspaceModel should not construct agent send sessions inline.")
        XCTAssertFalse(modelText.contains("activeRunner.send("), "WorkspaceModel should not own the low-level send call.")
        XCTAssertFalse(modelText.contains("WorkspaceMemoryRememberToolExecutor.didSaveMemory(in: thread)"), "WorkspaceModel should not inspect memory events after each send.")
    }

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
        let composerText = try Self.appSourceText(named: "WorkspaceModelComposer.swift")
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
        XCTAssertTrue(composerText.contains("WorkspaceSlashCommandDispatchPlanner.action("), "WorkspaceModel composer APIs should consume the slash dispatch planner.")
        XCTAssertTrue(composerText.contains("runSlashCommandDispatchAction(action, workspaceRoot: workspaceRoot)"), "WorkspaceModel composer APIs should delegate typed slash action application.")
        XCTAssertTrue(plannerTests.contains("testExternalCommandFamiliesMapToTypedActions"), "Slash dispatch families should have focused planner coverage.")
        XCTAssertFalse(modelText.contains("WorkspaceSlashCommandDispatchPlanner.action("), "WorkspaceModel.swift should not own slash dispatch planning.")
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
