import XCTest

final class ParitySlashRepositoryParserGateTests: QuillCodeParityTestCase {
    func testSlashParserDelegatesPullRequestSubcommands() throws {
        let slashText = try Self.appSourceText(named: "SlashCommand.swift")
        let parserText = try Self.appSourceText(named: "SlashPullRequestCommandParser.swift")
        let parserTests = try Self.appTestSourceText(named: "SlashPullRequestCommandParserTests.swift")

        Self.assertSource(slashText, contains: "SlashPullRequestCommandParser.parse(argument)")
        [
            "enum SlashPullRequestCommandParser",
            "selectorAndBody",
            "parseReviewers",
            "parseLabels"
        ].forEach { Self.assertSource(parserText, contains: $0) }
        Self.assertSource(
            parserTests,
            contains: "testReviewerLabelAndMergeCommandsBuildStructuredArguments"
        )
        [
            "func parsePullRequest",
            "func parseReviewers",
            "func parseLabels"
        ].forEach { Self.assertSource(slashText, excludes: $0) }
    }

    func testSlashParserDelegatesProjectSubcommands() throws {
        let slashText = try Self.appSourceText(named: "SlashCommand.swift")
        let parserText = try Self.appSourceText(named: "SlashProjectCommandParser.swift")
        let parserTests = try Self.appTestSourceText(named: "SlashProjectCommandParserTests.swift")

        Self.assertSource(slashText, contains: "SlashProjectCommandParser.parse(argument)")
        [
            "enum SlashProjectCommandParser",
            "Usage: /project new",
            "project-new-chat",
            "project-refresh-context"
        ].forEach { Self.assertSource(parserText, contains: $0) }
        [
            "testProjectNavigationCommandsMapToWorkspaceCommands",
            "testProjectRenameCommandsTrimNames"
        ].forEach { Self.assertSource(parserTests, contains: $0) }
        [
            "private static func parseProject",
            "Unknown project command",
            "Usage: /project new"
        ].forEach { Self.assertSource(slashText, excludes: $0) }
    }

    func testSlashParserDelegatesRemoteProjectSubcommands() throws {
        let slashText = try Self.appSourceText(named: "SlashCommand.swift")
        let parserText = try Self.appSourceText(named: "SlashRemoteProjectCommandParser.swift")
        let parserTests = try Self.appTestSourceText(named: "SlashRemoteProjectCommandParserTests.swift")

        Self.assertSource(slashText, contains: "SlashRemoteProjectCommandParser.parse(argument)")
        [
            "enum SlashRemoteProjectCommandParser",
            "Usage: /ssh user@host:/absolute/path"
        ].forEach { Self.assertSource(parserText, contains: $0) }
        [
            "testRemoteProjectParsingTrimsAddress",
            "testTopLevelRemoteAliasesDelegateToRemoteProjectParser"
        ].forEach { Self.assertSource(parserTests, contains: $0) }
        [
            ".sshProject(argument)",
            "Usage: /ssh user@host:/absolute/path"
        ].forEach { Self.assertSource(slashText, excludes: $0) }
    }
}
