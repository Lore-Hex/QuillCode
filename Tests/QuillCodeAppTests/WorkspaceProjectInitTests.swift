import XCTest
@testable import QuillCodeApp
import QuillCodeCore
import QuillCodeTools

@MainActor
final class WorkspaceProjectInitTests: XCTestCase {
    private func makeModelWithLocalProject(files: [String]) throws -> (QuillCodeWorkspaceModel, URL) {
        let root = try makeQuillCodeTestDirectory()
        for file in files {
            try "x".write(to: root.appendingPathComponent(file), atomically: true, encoding: .utf8)
        }
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: root, name: "Demo")
        _ = model.newChat()
        return (model, root)
    }

    func testInitCreatesAgentsMarkdownAndReloadsInstructions() throws {
        let (model, root) = try makeModelWithLocalProject(files: ["Package.swift"])
        let projectID = try XCTUnwrap(model.root.selectedProjectID)

        XCTAssertTrue(model.runInitProject(projectID))

        let agents = root.appendingPathComponent("AGENTS.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: agents.path))
        let content = try String(contentsOf: agents, encoding: .utf8)
        XCTAssertTrue(content.contains("# Demo"))
        XCTAssertTrue(content.contains("`swift build`"))

        // The just-written file is loaded as the active project instructions.
        XCTAssertTrue(model.surface().topBar.instructionSources.contains { $0.hasSuffix("AGENTS.md") })
    }

    func testInitRefusesToOverwriteAnExistingAgentsMarkdown() throws {
        let (model, root) = try makeModelWithLocalProject(files: ["Package.swift"])
        let projectID = try XCTUnwrap(model.root.selectedProjectID)
        let agents = root.appendingPathComponent("AGENTS.md")
        let original = "# Hand-written instructions\nDo not clobber me.\n"
        try original.write(to: agents, atomically: true, encoding: .utf8)

        XCTAssertFalse(model.runInitProject(projectID))

        // The user's file is byte-unchanged — the load-bearing guard held.
        XCTAssertEqual(try String(contentsOf: agents, encoding: .utf8), original)
    }

    func testInitRefusesWhenProjectAlreadyHasQuillcodeRules() throws {
        let (model, root) = try makeModelWithLocalProject(files: ["Package.swift"])
        let projectID = try XCTUnwrap(model.root.selectedProjectID)
        let quillcode = root.appendingPathComponent(".quillcode")
        try FileManager.default.createDirectory(at: quillcode, withIntermediateDirectories: true)
        try "Existing rules.\n".write(to: quillcode.appendingPathComponent("rules.md"), atomically: true, encoding: .utf8)

        // The project is already instructed via .quillcode/rules.md — /init must not add a
        // conflicting generic AGENTS.md on top of it.
        XCTAssertFalse(model.runInitProject(projectID))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("AGENTS.md").path))
    }

    func testInitRefusesWhenAgentsIsADanglingSymlink() throws {
        let (model, root) = try makeModelWithLocalProject(files: ["Package.swift"])
        let projectID = try XCTUnwrap(model.root.selectedProjectID)
        let link = root.appendingPathComponent("AGENTS.md")
        // A deliberate symlink to a shared (currently-absent) instruction file.
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "../shared/AGENTS.md")

        XCTAssertFalse(model.runInitProject(projectID))
        // The symlink is preserved (not replaced by a regular scaffold file).
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(atPath: link.path)[.type] as? FileAttributeType,
            .typeSymbolicLink
        )
    }

    func testInitIsReachableViaTheProjectInitCommand() throws {
        let (model, root) = try makeModelWithLocalProject(files: ["go.mod"])

        // Driving the command id (palette/slash both resolve to it) initializes the project.
        XCTAssertTrue(model.runWorkspaceCommand("project-init", workspaceRoot: root))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("AGENTS.md").path))
    }
}
