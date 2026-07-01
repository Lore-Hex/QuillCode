import XCTest

final class ParityWorkspaceViewCommandGateTests: QuillCodeParityTestCase {
    func testWorkspaceViewDelegatesCommandPlanning() throws {
        let viewText = try Self.appSourceText(named: "WorkspaceSwiftUIView.swift")
        let plannerText = try Self.appSourceText(
            named: "QuillCodeWorkspaceViewCommandPlanner.swift"
        )

        Self.assertSource(plannerText, containsAll: [
            "struct WorkspaceViewCommandPlanner",
            "enum WorkspaceViewCommandAction",
            "case \"settings\", \"computer-use-setup\"",
            "case \"thread-rename\"",
            "case \"project-rename\"",
            "shouldFocusComposer(afterDispatching:"
        ])
        Self.assertSource(viewText, contains: "WorkspaceViewCommandPlanner(")
        Self.assertSource(viewText, excludesAll: [
            "command.id == \"settings\"",
            "command.id == \"computer-use-setup\"",
            "command.id == \"thread-rename\"",
            "command.id == \"project-rename\"",
            "SlashCommandCatalog.insertText(forCommandPaletteID:"
        ])
    }
}
