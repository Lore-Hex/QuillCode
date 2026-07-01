import XCTest

final class ParityToolGateTests: QuillCodeParityTestCase {
    func testToolArgumentJSONSerializationLivesInCore() throws {
        let argumentsText = try Self.coreSourceText(named: "Arguments.swift")
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let slashText = try Self.appSourceText(named: "SlashCommand.swift")
        let pullRequestSlashText = try Self.appSourceText(named: "SlashPullRequestCommandParser.swift")
        let shellPlannerText = try Self.appSourceText(named: "WorkspaceShellToolCallPlanner.swift")
        let worktreePlannerText = try Self.appSourceText(named: "WorkspaceWorktreeToolCallPlanner.swift")
        let reviewPlannerText = try Self.appSourceText(named: "WorkspaceReviewActionToolCallPlanner.swift")

        XCTAssertTrue(
            argumentsText.contains("public static func json(_ values: [String: Any])"),
            "Mixed tool argument JSON serialization should live in QuillCodeCore."
        )
        XCTAssertTrue(
            pullRequestSlashText.contains("ToolArguments.json("),
            "Slash PR parser should use the shared core tool-argument serializer."
        )
        XCTAssertTrue(
            shellPlannerText.contains("ToolArguments.json("),
            "Shell tool-call planners should use the shared core tool-argument serializer."
        )
        XCTAssertTrue(
            worktreePlannerText.contains("ToolArguments.json("),
            "Worktree tool-call planners should use the shared core tool-argument serializer."
        )
        XCTAssertTrue(
            reviewPlannerText.contains("ToolArguments.json("),
            "Review action tool-call planners should use the shared core tool-argument serializer."
        )
        XCTAssertFalse(
            modelText.contains("private func toolArgumentsJSON"),
            "WorkspaceModel should not own ad hoc JSON serialization."
        )
        XCTAssertFalse(
            modelText.contains("JSONSerialization"),
            "WorkspaceModel should not own JSON serialization."
        )
        XCTAssertFalse(
            slashText.contains("private static func json(_ values: [String: Any])"),
            "SlashCommand should not own ad hoc JSON serialization."
        )
    }

    func testSlashCommandCatalogLivesOutsideParser() throws {
        let slashText = try Self.appSourceText(named: "SlashCommand.swift")
        let pullRequestSlashText = try Self.appSourceText(named: "SlashPullRequestCommandParser.swift")
        let catalogText = try Self.appSourceText(named: "SlashCommandCatalog.swift")

        Self.assertSource(catalogText, contains: "public struct SlashCommandSuggestionSurface")
        Self.assertSource(catalogText, contains: "struct SlashCommandDefinition")
        Self.assertSource(catalogText, contains: "enum SlashCommandCatalog")
        Self.assertSource(catalogText, contains: "static let definitions")
        Self.assertSource(catalogText, contains: "static func suggestions")
        Self.assertSource(slashText, contains: "enum SlashCommandParser")
        Self.assertSource(pullRequestSlashText, contains: "ToolArguments.json(")
        Self.assertSource(slashText, excludes: "public struct SlashCommandSuggestionSurface")
        Self.assertSource(slashText, excludes: "struct SlashCommandDefinition")
        Self.assertSource(slashText, excludes: "static let definitions")
        Self.assertSource(slashText, excludes: "private static func score")
    }

}
