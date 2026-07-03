import XCTest

final class ParitySlashThreadMemoryParserGateTests: QuillCodeParityTestCase {
    func testSlashParserDelegatesThreadLifecycleSubcommands() throws {
        let slashText = try Self.appSourceText(named: "SlashCommand.swift")
        let parserText = try Self.appSourceText(named: "SlashThreadCommandParser.swift")
        let parserTests = try Self.appTestSourceText(named: "SlashThreadCommandParserTests.swift")

        Self.assertSource(slashText, contains: "SlashThreadCommandParser.supports(threadCommand)")
        Self.assertSource(
            slashText,
            contains: "SlashThreadCommandParser.parse(name: threadCommand, argument: argument)"
        )
        [
            "enum SlashThreadCommandParser",
            "Usage: /rename New chat title",
            "thread-clear",
            "thread-duplicate",
            "thread-delete"
        ].forEach { Self.assertSource(parserText, contains: $0) }
        [
            "testSupportsThreadLifecycleAliases",
            "testClearAliasesMapToThreadClearCommand",
            "testRenameAliasesTrimTitlesAndValidateRequiredTitle"
        ].forEach { Self.assertSource(parserTests, contains: $0) }
        [
            ".renameThread(argument)",
            "Usage: /rename New chat title",
            "thread-clear",
            "thread-duplicate",
            "thread-delete",
            "compact-context"
        ].forEach { Self.assertSource(slashText, excludes: $0) }
    }

    func testSlashParserDelegatesMemorySubcommands() throws {
        let slashText = try Self.appSourceText(named: "SlashCommand.swift")
        let parserText = try Self.appSourceText(named: "SlashMemoryCommandParser.swift")
        let parserTests = try Self.appTestSourceText(named: "SlashMemoryCommandParserTests.swift")

        Self.assertSource(slashText, contains: "SlashMemoryCommandParser.supports(memoryCommand)")
        Self.assertSource(
            slashText,
            contains: "SlashMemoryCommandParser.parse(name: memoryCommand, argument: argument)"
        )
        [
            "enum SlashMemoryCommandParser",
            "toggle-memories"
        ].forEach { Self.assertSource(parserText, contains: $0) }
        [
            "testMemoryPaneAliasesToggleMemoriesPane",
            "testRememberWithContentTrimsAndBuildsRememberCommand"
        ].forEach { Self.assertSource(parserTests, contains: $0) }
        [
            "case \"memory\", \"memories\"",
            "case \"remember\"",
            "toggle-memories"
        ].forEach { Self.assertSource(slashText, excludes: $0) }
    }
}
