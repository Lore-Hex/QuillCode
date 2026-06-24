import XCTest

final class ParitySlashGateTests: QuillCodeParityTestCase {
    func testSlashParserDelegatesPullRequestSubcommands() throws {
        let slashText = try Self.appSourceText(named: "SlashCommand.swift")
        let pullRequestParserText = try Self.appSourceText(named: "SlashPullRequestCommandParser.swift")
        let pullRequestParserTests = try Self.appTestSourceText(named: "SlashPullRequestCommandParserTests.swift")

        XCTAssertTrue(slashText.contains("SlashPullRequestCommandParser.parse(argument)"), "Outer slash parser should delegate PR subcommands.")
        XCTAssertTrue(pullRequestParserText.contains("enum SlashPullRequestCommandParser"), "PR slash parsing should live in a focused parser.")
        XCTAssertTrue(pullRequestParserText.contains("selectorAndBody"), "PR selector/body parsing should live with PR parser semantics.")
        XCTAssertTrue(pullRequestParserText.contains("parseReviewers"), "Reviewer subcommand parsing should live with PR parser semantics.")
        XCTAssertTrue(pullRequestParserText.contains("parseLabels"), "Label subcommand parsing should live with PR parser semantics.")
        XCTAssertTrue(pullRequestParserTests.contains("testReviewerLabelAndMergeCommandsBuildStructuredArguments"), "PR parser structured arguments should have focused unit coverage.")
        XCTAssertFalse(slashText.contains("func parsePullRequest"), "Outer slash parser should not own PR parsing internals.")
        XCTAssertFalse(slashText.contains("func parseReviewers"), "Outer slash parser should not own PR reviewer parsing internals.")
        XCTAssertFalse(slashText.contains("func parseLabels"), "Outer slash parser should not own PR label parsing internals.")
    }

    func testSlashParserDelegatesProjectSubcommands() throws {
        let slashText = try Self.appSourceText(named: "SlashCommand.swift")
        let projectParserText = try Self.appSourceText(named: "SlashProjectCommandParser.swift")
        let projectParserTests = try Self.appTestSourceText(named: "SlashProjectCommandParserTests.swift")

        XCTAssertTrue(slashText.contains("SlashProjectCommandParser.parse(argument)"), "Outer slash parser should delegate project subcommands.")
        XCTAssertTrue(projectParserText.contains("enum SlashProjectCommandParser"), "Project slash parsing should live in a focused parser.")
        XCTAssertTrue(projectParserText.contains("Usage: /project new"), "Project usage copy should live with project parser semantics.")
        XCTAssertTrue(projectParserText.contains("project-new-chat"), "Project command IDs should live with project parser semantics.")
        XCTAssertTrue(projectParserText.contains("project-refresh-context"), "Project refresh aliases should live with project parser semantics.")
        XCTAssertTrue(projectParserTests.contains("testProjectNavigationCommandsMapToWorkspaceCommands"), "Project aliases should have focused parser coverage.")
        XCTAssertTrue(projectParserTests.contains("testProjectRenameCommandsTrimNames"), "Project rename parsing should have focused parser coverage.")
        XCTAssertFalse(slashText.contains("private static func parseProject"), "Outer slash parser should not own project parsing internals.")
        XCTAssertFalse(slashText.contains("Unknown project command"), "Outer slash parser should not own project error copy.")
        XCTAssertFalse(slashText.contains("Usage: /project new"), "Outer slash parser should not own project usage copy.")
    }

    func testSlashParserDelegatesTerminalSubcommands() throws {
        let slashText = try Self.appSourceText(named: "SlashCommand.swift")
        let terminalParserText = try Self.appSourceText(named: "SlashTerminalCommandParser.swift")
        let terminalParserTests = try Self.appTestSourceText(named: "SlashTerminalCommandParserTests.swift")

        XCTAssertTrue(slashText.contains("SlashTerminalCommandParser.parse(argument)"), "Outer slash parser should delegate terminal subcommands.")
        XCTAssertTrue(terminalParserText.contains("enum SlashTerminalCommandParser"), "Terminal slash parsing should live in a focused parser.")
        XCTAssertTrue(terminalParserText.contains("toggle-terminal"), "Terminal toggle command ID should live with terminal parser semantics.")
        XCTAssertTrue(terminalParserText.contains("terminal-clear"), "Terminal clear command ID should live with terminal parser semantics.")
        XCTAssertTrue(terminalParserText.contains("Usage: /terminal or /terminal clear"), "Terminal usage copy should live with terminal parser semantics.")
        XCTAssertTrue(terminalParserTests.contains("testTerminalToggleAliasesMapToWorkspaceCommand"), "Terminal toggle aliases should have focused parser coverage.")
        XCTAssertTrue(terminalParserTests.contains("testTerminalClearAliasesMapToWorkspaceCommand"), "Terminal clear aliases should have focused parser coverage.")
        XCTAssertFalse(slashText.contains("private static func parseTerminal"), "Outer slash parser should not own terminal parsing internals.")
        XCTAssertFalse(slashText.contains("Usage: /terminal or /terminal clear"), "Outer slash parser should not own terminal usage copy.")
        XCTAssertFalse(slashText.contains("terminal-clear"), "Outer slash parser should not own terminal command IDs.")
    }

    func testSlashParserDelegatesModeSubcommands() throws {
        let slashText = try Self.appSourceText(named: "SlashCommand.swift")
        let modeParserText = try Self.appSourceText(named: "SlashModeCommandParser.swift")
        let modeParserTests = try Self.appTestSourceText(named: "SlashModeCommandParserTests.swift")

        XCTAssertTrue(slashText.contains("SlashModeCommandParser.parse(argument)"), "Outer slash parser should delegate mode arguments.")
        XCTAssertTrue(modeParserText.contains("enum SlashModeCommandParser"), "Mode slash parsing should live in a focused parser.")
        XCTAssertTrue(modeParserText.contains("read-only"), "Read-only aliases should live with mode parser semantics.")
        XCTAssertTrue(modeParserText.contains("Unknown mode"), "Mode error copy should live with mode parser semantics.")
        XCTAssertTrue(modeParserText.contains("Usage: /mode auto"), "Mode usage copy should live with mode parser semantics.")
        XCTAssertTrue(modeParserTests.contains("testModeAliasesMapToAgentModes"), "Mode aliases should have focused parser coverage.")
        XCTAssertTrue(modeParserTests.contains("testUnknownModeReturnsTrimmedArgumentInError"), "Mode error copy should have focused parser coverage.")
        XCTAssertFalse(slashText.contains("private static func parseMode"), "Outer slash parser should not own mode parsing internals.")
        XCTAssertFalse(slashText.contains("Unknown mode"), "Outer slash parser should not own mode error copy.")
        XCTAssertFalse(slashText.contains("Usage: /mode auto"), "Outer slash parser should not own mode usage copy.")
    }

    func testSlashParserDelegatesSchedulingSubcommands() throws {
        let slashText = try Self.appSourceText(named: "SlashCommand.swift")
        let schedulingParserText = try Self.appSourceText(named: "SlashSchedulingCommandParser.swift")
        let schedulingParserTests = try Self.appTestSourceText(named: "SlashSchedulingCommandParserTests.swift")

        XCTAssertTrue(slashText.contains("SlashSchedulingCommandParser.parseThreadFollowUp(argument)"), "Outer slash parser should delegate thread follow-up scheduling.")
        XCTAssertTrue(slashText.contains("SlashSchedulingCommandParser.parseWorkspaceSchedule(argument)"), "Outer slash parser should delegate workspace scheduling.")
        XCTAssertTrue(schedulingParserText.contains("enum SlashSchedulingCommandParser"), "Scheduling slash parsing should live in a focused parser.")
        XCTAssertTrue(schedulingParserText.contains("Usage: /follow-up in 30 minutes"), "Follow-up usage copy should live with scheduling parser semantics.")
        XCTAssertTrue(schedulingParserText.contains("Usage: /workspace-check in 1 hour"), "Workspace-check usage copy should live with scheduling parser semantics.")
        XCTAssertTrue(schedulingParserTests.contains("testThreadFollowUpSchedulesTrimmedArgument"), "Follow-up schedule trimming should have focused parser coverage.")
        XCTAssertTrue(schedulingParserTests.contains("testWorkspaceScheduleSchedulesTrimmedArgument"), "Workspace schedule trimming should have focused parser coverage.")
        XCTAssertTrue(schedulingParserTests.contains("testTopLevelSchedulingAliasesDelegateToSchedulingParser"), "Scheduling aliases should have focused parser coverage.")
        XCTAssertFalse(slashText.contains(".threadFollowUp(argument)"), "Outer slash parser should not build thread follow-up commands inline.")
        XCTAssertFalse(slashText.contains(".workspaceSchedule(argument)"), "Outer slash parser should not build workspace schedule commands inline.")
        XCTAssertFalse(slashText.contains("Usage: /follow-up in 30 minutes"), "Outer slash parser should not own follow-up usage copy.")
        XCTAssertFalse(slashText.contains("Usage: /workspace-check in 1 hour"), "Outer slash parser should not own workspace-check usage copy.")
    }
}
