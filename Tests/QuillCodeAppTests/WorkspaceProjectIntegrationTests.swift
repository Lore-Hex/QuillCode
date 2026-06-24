import XCTest
@testable import QuillCodeApp

@MainActor
final class WorkspaceProjectIntegrationTests: XCTestCase {
    func testProjectInstructionsLoadIntoNewThreadsAndRefreshBeforeRun() async throws {
        let root = try makeQuillCodeTestDirectory()
        try "Prefer Swift tests before final answers.\n".write(
            to: root.appendingPathComponent("AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )
        let quillcodeDirectory = root.appendingPathComponent(".quillcode")
        try FileManager.default.createDirectory(at: quillcodeDirectory, withIntermediateDirectories: true)
        try "Use small focused commits.\n".write(
            to: quillcodeDirectory.appendingPathComponent("rules.md"),
            atomically: true,
            encoding: .utf8
        )

        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "Rules Project")
        let threadID = model.newChat(projectID: projectID)

        XCTAssertEqual(model.root.projects.first?.instructions.map(\.path), [
            "AGENTS.md",
            ".quillcode/rules.md"
        ])
        XCTAssertEqual(model.root.threads.first { $0.id == threadID }?.instructions.count, 2)
        XCTAssertEqual(model.surface().topBar.instructionLabel, "2 instruction files loaded")

        try "Prefer targeted unit tests.\n".write(
            to: root.appendingPathComponent("AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )
        model.setDraft("run whoami")
        await model.submitComposer(workspaceRoot: root)

        XCTAssertTrue(model.selectedThread?.instructions.first?.content.contains("targeted unit tests") == true)
    }
}
