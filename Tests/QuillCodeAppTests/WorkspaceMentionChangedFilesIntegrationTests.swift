import XCTest
@testable import QuillCodeApp
import QuillCodeCore
import QuillCodeTools

@MainActor
final class WorkspaceMentionChangedFilesIntegrationTests: XCTestCase {
    private func gitStatusCall() -> ToolCall {
        ToolCall(name: ToolDefinition.gitStatus.name, argumentsJSON: ToolArguments.json([:]))
    }

    /// A git repo with `Sources/App.swift` and `Sources/Admin.swift` committed, then
    /// `Sources/Admin.swift` modified so `git status` reports it changed.
    private func makeRepoWithModifiedAdmin() throws -> URL {
        let root = try makeTempGitRepoWithInitialCommit()
        let executor = FileToolExecutor(workspaceRoot: root)
        XCTAssertTrue(executor.write(path: "Sources/App.swift", content: "struct App {}\n").ok)
        XCTAssertTrue(executor.write(path: "Sources/Admin.swift", content: "struct Admin {}\n").ok)
        _ = try runGit(["add", "."], cwd: root)
        _ = try runGit(["commit", "-m", "add sources"], cwd: root)
        XCTAssertTrue(executor.write(path: "Sources/Admin.swift", content: "struct Admin { let x = 1 }\n").ok)
        return root
    }

    private func makeLocalProject(files: [String]) throws -> URL {
        let root = try makeQuillCodeTestDirectory()
        let executor = FileToolExecutor(workspaceRoot: root)
        for path in files {
            XCTAssertTrue(executor.write(path: path, content: "// \(path)\n").ok)
        }
        return root
    }

    func testGitStatusRunBoostsAndFlagsChangedFilesInMentions() throws {
        let root = try makeRepoWithModifiedAdmin()
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: root, name: "Demo")
        _ = model.newChat()

        // Before any git status: text ranking puts the shorter App.swift first, nothing flagged.
        XCTAssertTrue(model.changedFilePaths.isEmpty)
        model.setDraft("open @a")
        let before = model.surface().composer.fileMentionSuggestions
        XCTAssertEqual(before.first?.path, "Sources/App.swift")
        XCTAssertFalse(before.contains(where: \.isChanged))

        // One git status run captures BOTH the branch chip and the changed-file set.
        let result = model.runToolCall(gitStatusCall(), workspaceRoot: root)
        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertNotNil(model.surface().topBar.branchStatusLabel)
        XCTAssertTrue(model.changedFilePaths.contains("Sources/Admin.swift"))

        // Now the changed file is boosted to the top and flagged; the unchanged file is not.
        model.setDraft("open @a")
        let after = model.surface().composer.fileMentionSuggestions
        XCTAssertEqual(after.first?.path, "Sources/Admin.swift")
        XCTAssertTrue(after.first?.isChanged ?? false)
        XCTAssertEqual(after.first(where: { $0.path == "Sources/App.swift" })?.isChanged, false)
    }

    func testChangedSetDoesNotBleedIntoAnotherProjectsMentions() throws {
        let root = try makeRepoWithModifiedAdmin()
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: root, name: "Demo")
        _ = model.runToolCall(gitStatusCall(), workspaceRoot: root)
        XCTAssertTrue(model.changedFilePaths.contains("Sources/Admin.swift"))

        // Switch to another project that ALSO has Sources/Admin.swift (unchanged there),
        // and open a conversation in it so it becomes the active mention context.
        let other = try makeLocalProject(files: ["Sources/Admin.swift"])
        _ = model.addProject(path: other, name: "Other")
        _ = model.newChat()

        model.setDraft("open @admin")
        let suggestions = model.surface().composer.fileMentionSuggestions
        XCTAssertEqual(suggestions.first?.path, "Sources/Admin.swift")
        // The first project's changed set must NOT flag the second project's identical path.
        XCTAssertFalse(suggestions.contains(where: \.isChanged))
    }

    func testChangedBadgeDoesNotSurviveACommitAndLaterToolRun() throws {
        let root = try makeRepoWithModifiedAdmin()
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: root, name: "Demo")
        _ = model.newChat()

        _ = model.runToolCall(gitStatusCall(), workspaceRoot: root)
        XCTAssertTrue(model.changedFilePaths.contains("Sources/Admin.swift"))

        // Commit the change so the working tree is clean, then run any other tool. The
        // index rebuild on that run must drop the now-stale changed set — a committed,
        // clean file must never keep its "Changed" badge.
        _ = try runGit(["add", "."], cwd: root)
        _ = try runGit(["commit", "-m", "commit admin"], cwd: root)
        _ = model.runToolCall(
            ToolCall(name: ToolDefinition.fileList.name, argumentsJSON: ToolArguments.json([:])),
            workspaceRoot: root
        )

        XCTAssertTrue(model.changedFilePaths.isEmpty)
        model.setDraft("open @admin")
        XCTAssertFalse(model.surface().composer.fileMentionSuggestions.contains(where: \.isChanged))
    }

    func testSelectingRemoteProjectClearsChangedFileSet() throws {
        let root = try makeRepoWithModifiedAdmin()
        let model = QuillCodeWorkspaceModel()
        _ = model.addProject(path: root, name: "Demo")
        _ = model.runToolCall(gitStatusCall(), workspaceRoot: root)
        XCTAssertFalse(model.changedFilePaths.isEmpty)

        _ = model.addSSHProject("user@host:/srv/app", name: "Remote")
        XCTAssertTrue(model.changedFilePaths.isEmpty)
    }
}
