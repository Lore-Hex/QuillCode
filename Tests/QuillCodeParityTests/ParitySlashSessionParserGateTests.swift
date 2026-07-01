import XCTest

final class ParitySlashSessionParserGateTests: QuillCodeParityTestCase {
    func testSlashParserDelegatesTerminalSubcommands() throws {
        let slashText = try Self.appSourceText(named: "SlashCommand.swift")
        let parserText = try Self.appSourceText(named: "SlashTerminalCommandParser.swift")
        let parserTests = try Self.appTestSourceText(named: "SlashTerminalCommandParserTests.swift")

        Self.assertSource(slashText, contains: "SlashTerminalCommandParser.parse(argument)")
        [
            "enum SlashTerminalCommandParser",
            "toggle-terminal",
            "terminal-clear",
            "Usage: /terminal or /terminal clear"
        ].forEach { Self.assertSource(parserText, contains: $0) }
        [
            "testTerminalToggleAliasesMapToWorkspaceCommand",
            "testTerminalClearAliasesMapToWorkspaceCommand"
        ].forEach { Self.assertSource(parserTests, contains: $0) }
        [
            "private static func parseTerminal",
            "Usage: /terminal or /terminal clear",
            "terminal-clear"
        ].forEach { Self.assertSource(slashText, excludes: $0) }
    }

    func testSlashParserDelegatesModeSubcommands() throws {
        let slashText = try Self.appSourceText(named: "SlashCommand.swift")
        let parserText = try Self.appSourceText(named: "SlashModeCommandParser.swift")
        let parserTests = try Self.appTestSourceText(named: "SlashModeCommandParserTests.swift")

        Self.assertSource(slashText, contains: "SlashModeCommandParser.parse(argument)")
        [
            "enum SlashModeCommandParser",
            "read-only",
            "Unknown mode",
            "Usage: /mode auto"
        ].forEach { Self.assertSource(parserText, contains: $0) }
        [
            "testModeAliasesMapToAgentModes",
            "testUnknownModeReturnsTrimmedArgumentInError"
        ].forEach { Self.assertSource(parserTests, contains: $0) }
        [
            "private static func parseMode",
            "Unknown mode",
            "Usage: /mode auto"
        ].forEach { Self.assertSource(slashText, excludes: $0) }
    }

    func testSlashParserDelegatesModelSubcommands() throws {
        let slashText = try Self.appSourceText(named: "SlashCommand.swift")
        let parserText = try Self.appSourceText(named: "SlashModelCommandParser.swift")
        let parserTests = try Self.appTestSourceText(named: "SlashModelCommandParserTests.swift")

        Self.assertSource(slashText, contains: "SlashModelCommandParser.parse(argument)")
        [
            "enum SlashModelCommandParser",
            "Usage: /model /synth"
        ].forEach { Self.assertSource(parserText, contains: $0) }
        [
            "testModelParsingTrimsModelArgument",
            "testTopLevelModelCommandDelegatesToModelParser"
        ].forEach { Self.assertSource(parserTests, contains: $0) }
        [
            ".model(argument)",
            "Usage: /model /synth"
        ].forEach { Self.assertSource(slashText, excludes: $0) }
    }
}
