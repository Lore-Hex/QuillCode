import XCTest
@testable import QuillCodeApp
import QuillCodeTools

@MainActor
final class WorkspaceFileMentionIntegrationTests: XCTestCase {
    private func makeProject(files: [String]) throws -> URL {
        let root = try makeQuillCodeTestDirectory()
        let executor = FileToolExecutor(workspaceRoot: root)
        for path in files {
            XCTAssertTrue(executor.write(path: path, content: "// \(path)\n").ok)
        }
        return root
    }

    func testAddingLocalProjectPopulatesFileMentionIndex() throws {
        let root = try makeProject(files: ["Sources/App.swift", "README.md"])
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: root, name: "Demo")

        let paths = model.fileMentionIndex.entries.map(\.path)
        XCTAssertTrue(paths.contains("Sources/App.swift"))
        XCTAssertTrue(paths.contains("README.md"))
    }

    func testComposerSurfaceSuggestsWorkspaceFilesForActiveMention() throws {
        let root = try makeProject(files: ["Sources/App.swift", "Sources/Helper.swift"])
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: root, name: "Demo")

        model.setDraft("please read @App")
        let suggestions = model.surface().composer.fileMentionSuggestions

        XCTAssertEqual(suggestions.first?.path, "Sources/App.swift")
        XCTAssertEqual(suggestions.first?.insertText, "please read @Sources/App.swift ")
    }

    func testComposerSurfaceHasNoMentionSuggestionsWithoutActiveMention() throws {
        let root = try makeProject(files: ["Sources/App.swift"])
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: root, name: "Demo")

        model.setDraft("no mention here")
        XCTAssertTrue(model.surface().composer.fileMentionSuggestions.isEmpty)
    }

    func testSlashCommandDraftSuppressesFileMentionSuggestions() throws {
        let root = try makeProject(files: ["Sources/App.swift"])
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: root, name: "Demo")

        model.setDraft("/help")
        let surface = model.surface().composer
        XCTAssertFalse(surface.slashSuggestions.isEmpty)
        XCTAssertTrue(surface.fileMentionSuggestions.isEmpty)
    }

    func testRefreshContextPicksUpNewlyCreatedFiles() throws {
        let root = try makeProject(files: ["Sources/App.swift"])
        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: "Demo")

        XCTAssertTrue(FileToolExecutor(workspaceRoot: root).write(path: "Sources/Added.swift", content: "// new\n").ok)
        XCTAssertFalse(model.fileMentionIndex.entries.map(\.path).contains("Sources/Added.swift"))

        _ = model.refreshProjectContext(projectID)
        XCTAssertTrue(model.fileMentionIndex.entries.map(\.path).contains("Sources/Added.swift"))
    }

    func testFileMentionIndexRefreshesAfterAgentFileWrite() async throws {
        let root = try makeQuillCodeTestDirectory()
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: root, name: "Demo")
        XCTAssertFalse(model.fileMentionIndex.entries.map(\.path).contains("hello.txt"))

        model.setDraft("Can you write a file that says hello world")
        await model.submitComposer(workspaceRoot: root)

        XCTAssertTrue(model.fileMentionIndex.entries.map(\.path).contains("hello.txt"))
    }

    func testSelectingSSHRemoteProjectClearsFileMentionIndex() throws {
        let root = try makeProject(files: ["Sources/App.swift"])
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: root, name: "Demo")
        XCTAssertFalse(model.fileMentionIndex.isEmpty)

        _ = model.addSSHProject("user@host:/srv/app", name: "Remote")
        XCTAssertTrue(model.fileMentionIndex.isEmpty)
    }
}
