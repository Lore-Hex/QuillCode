import XCTest

final class ParitySlashWorkspaceParserGateTests: QuillCodeParityTestCase {
    func testSlashParserDelegatesWorkspaceSubcommands() throws {
        let slashText = try Self.appSourceText(named: "SlashCommand.swift")
        let parserText = try Self.appSourceText(named: "SlashWorkspaceCommandParser.swift")
        let worktreeText = try Self.appSourceText(named: "SlashWorktreeCommandParser.swift")
        let parserTests = try Self.appTestSourceText(named: "SlashWorkspaceCommandParserTests.swift")

        Self.assertSource(slashText, contains: "SlashWorkspaceCommandParser.supports(workspaceCommand)")
        Self.assertSource(
            slashText,
            contains: "SlashWorkspaceCommandParser.parse(name: workspaceCommand, argument: argument)"
        )
        [
            "enum SlashWorkspaceCommandParser",
            "toggle-browser",
            "SlashWorktreeCommandParser.parse(argument)"
        ].forEach { Self.assertSource(parserText, contains: $0) }
        [
            "enum SlashWorktreeCommandParser",
            "git-worktree-list",
            ".worktreeCreate",
            ".worktreeOpen",
            ".worktreeRemove",
            ".worktreePrune"
        ].forEach { Self.assertSource(worktreeText, contains: $0) }
        [
            "testBrowserAliasesToggleBrowserPane",
            "testWorktreeAliasesListGitWorktrees",
            "testWorktreeCreateParsesPathBranchAndBase",
            "testWorktreeOpenAndRemoveParseTypedRequests",
            "testWorktreePruneParsesTypedRequest"
        ].forEach { Self.assertSource(parserTests, contains: $0) }
        [
            "case \"browser\", \"preview\"",
            "case \"worktree\", \"worktrees\", \"wt\"",
            "toggle-browser",
            "git-worktree-list"
        ].forEach { Self.assertSource(slashText, excludes: $0) }
    }

    func testSlashParserDelegatesEnvironmentSubcommands() throws {
        let slashText = try Self.appSourceText(named: "SlashCommand.swift")
        let parserText = try Self.appSourceText(named: "SlashEnvironmentCommandParser.swift")
        let parserTests = try Self.appTestSourceText(named: "SlashEnvironmentCommandParserTests.swift")

        Self.assertSource(slashText, contains: "SlashEnvironmentCommandParser.supports(environmentCommand)")
        Self.assertSource(slashText, contains: "SlashEnvironmentCommandParser.parse(argument)")
        [
            "enum SlashEnvironmentCommandParser",
            #""env", "environment", "local-env""#,
            "value.firstTokenSplit",
            ".environmentSchedule(trimmed)",
            ".environmentAction(nil)",
            ".environmentAction(value)"
        ].forEach { Self.assertSource(parserText, contains: $0) }
        [
            "testEmptyEnvironmentArgumentListsActions",
            "testEnvironmentActionQueryIsTrimmed",
            "testEnvironmentScheduleIsParsedSeparatelyFromImmediateAction"
        ].forEach { Self.assertSource(parserTests, contains: $0) }
        [
            #"case "env", "environment", "local-env""#,
            ".environmentAction(argument.isEmpty ? nil : argument)"
        ].forEach { Self.assertSource(slashText, excludes: $0) }
    }

    func testSlashParserDelegatesSchedulingSubcommands() throws {
        let slashText = try Self.appSourceText(named: "SlashCommand.swift")
        let parserText = try Self.appSourceText(named: "SlashSchedulingCommandParser.swift")
        let parserTests = try Self.appTestSourceText(named: "SlashSchedulingCommandParserTests.swift")

        Self.assertSource(slashText, contains: "SlashSchedulingCommandParser.parseThreadFollowUp(argument)")
        Self.assertSource(slashText, contains: "SlashSchedulingCommandParser.parseWorkspaceSchedule(argument)")
        [
            "enum SlashSchedulingCommandParser",
            "Usage: /follow-up in 30 minutes",
            "Usage: /workspace-check in 1 hour"
        ].forEach { Self.assertSource(parserText, contains: $0) }
        [
            "testThreadFollowUpSchedulesTrimmedArgument",
            "testWorkspaceScheduleSchedulesTrimmedArgument",
            "testTopLevelSchedulingAliasesDelegateToSchedulingParser"
        ].forEach { Self.assertSource(parserTests, contains: $0) }
        [
            ".threadFollowUp(argument)",
            ".workspaceSchedule(argument)",
            "Usage: /follow-up in 30 minutes",
            "Usage: /workspace-check in 1 hour"
        ].forEach { Self.assertSource(slashText, excludes: $0) }
    }
}
