import XCTest

final class ParityWorkspaceExecutionSlashGateTests: QuillCodeParityTestCase {
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

}
