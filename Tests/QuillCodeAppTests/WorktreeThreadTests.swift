import XCTest
import Foundation
import QuillCodeCore
@testable import QuillCodeApp

// MARK: - Unit: the pure planner

final class WorktreeThreadPlannerTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/work/MyRepo")

    func testSlugifies() {
        XCTAssertEqual(WorktreeThreadPlanner.slug(from: "Add Login Flow!"), "add-login-flow")
        XCTAssertEqual(WorktreeThreadPlanner.slug(from: "  spaced  out  "), "spaced-out")
        XCTAssertNil(WorktreeThreadPlanner.slug(from: "  !!!  "))
        XCTAssertNil(WorktreeThreadPlanner.slug(from: nil))
    }

    func testBranchAndSiblingPath() {
        let req = WorktreeThreadPlanner.plan(projectRoot: root, baseBranch: "main", name: "Try It", existingBranches: [])
        XCTAssertEqual(req.branch, "quill/try-it")
        XCTAssertEqual(req.base, "main")
        // sibling of the project root, named <project>-<leaf>
        XCTAssertEqual(req.path, "/work/MyRepo-try-it")
    }

    func testDefaultNameWhenNil() {
        let req = WorktreeThreadPlanner.plan(projectRoot: root, baseBranch: "main", name: nil, existingBranches: [])
        XCTAssertEqual(req.branch, "quill/work")
        XCTAssertEqual(req.path, "/work/MyRepo-work")
    }

    func testAvoidsBranchCollision() {
        let req = WorktreeThreadPlanner.plan(
            projectRoot: root, baseBranch: "main", name: "work",
            existingBranches: ["quill/work", "quill/work-2"]
        )
        XCTAssertEqual(req.branch, "quill/work-3")
        XCTAssertEqual(req.path, "/work/MyRepo-work-3")
    }
}

// MARK: - Functional/integration: newWorktreeThread through the model against a real git repo

@MainActor
final class WorktreeThreadModelTests: XCTestCase {
    private func makeGitRepo() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wtthread-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let shell = { (cmd: String) in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-lc", cmd]
            p.currentDirectoryURL = dir
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
            try? p.run(); p.waitUntilExit()
        }
        shell("git init -q && git config user.email t@t.co && git config user.name t && git config commit.gpgsign false")
        try "hello\n".write(to: dir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        shell("git add -A && git commit -q -m init")
        return dir
    }

    func testNewWorktreeThreadCreatesIsolatedBoundThreadInSameProject() throws {
        let repo = try makeGitRepo()
        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: repo, name: "Repo")
        model.selectProject(projectID)
        let localThread = model.newChat(projectID: projectID)

        let worktreeThread = model.newWorktreeThread(name: "experiment")
        XCTAssertNotNil(worktreeThread, "worktree thread should be created")
        XCTAssertNotEqual(worktreeThread, localThread)

        // The new thread stays in the SAME project but is bound to its own worktree directory.
        XCTAssertEqual(model.selectedThread?.projectID, projectID)
        let binding = model.selectedThread?.worktree
        XCTAssertNotNil(binding)
        XCTAssertEqual(binding?.branch, "quill/experiment")
        XCTAssertTrue(binding.map(\.isResolvable) ?? false, "worktree dir should exist on disk")

        // Isolation: the bound thread runs in the worktree; the local thread in the project root.
        XCTAssertEqual(model.activeWorkspaceRoot?.standardizedFileURL,
                       URL(fileURLWithPath: binding!.path).standardizedFileURL)
        model.selectThread(localThread)
        XCTAssertEqual(model.activeWorkspaceRoot?.standardizedFileURL, repo.standardizedFileURL)

        // The real git worktree + branch exist.
        XCTAssertTrue(FileManager.default.fileExists(atPath: binding!.path))
    }

    func testNewWorktreeThreadIsNilWithoutLocalProject() throws {
        let model = QuillCodeWorkspaceModel()
        XCTAssertNil(model.newWorktreeThread(name: "x"), "no selected project → nil")
    }
}
