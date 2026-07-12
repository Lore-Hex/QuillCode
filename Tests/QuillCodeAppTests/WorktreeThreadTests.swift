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

    func testManagedRequestAndUniqueSiblingPath() {
        let plan = WorktreeThreadPlanner.plan(
            projectRoot: root,
            baseBranch: "main",
            name: "Try It",
            identifier: "ABCDEF12-3456"
        )
        XCTAssertEqual(plan.request.branch, "")
        XCTAssertEqual(plan.request.base, "main")
        XCTAssertTrue(plan.request.managed)
        XCTAssertEqual(plan.request.path, "/work/MyRepo-try-it-abcdef12")
        XCTAssertEqual(plan.title, "Worktree: try-it")
    }

    func testDefaultNameWhenNil() {
        let plan = WorktreeThreadPlanner.plan(
            projectRoot: root,
            baseBranch: "main",
            name: nil,
            identifier: "12345678"
        )
        XCTAssertEqual(plan.request.branch, "")
        XCTAssertEqual(plan.request.path, "/work/MyRepo-work-12345678")
        XCTAssertEqual(plan.title, "Worktree: work")
    }

    func testIdentifiersKeepSameNamePlansDistinct() {
        let first = WorktreeThreadPlanner.plan(
            projectRoot: root, baseBranch: "main", name: "work", identifier: "11111111"
        )
        let second = WorktreeThreadPlanner.plan(
            projectRoot: root, baseBranch: "main", name: "work", identifier: "22222222"
        )
        XCTAssertNotEqual(first.request.path, second.request.path)
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
        try "local edit\n".write(
            to: repo.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        try "local only\n".write(
            to: repo.appendingPathComponent("notes.txt"),
            atomically: true,
            encoding: .utf8
        )

        let worktreeThread = model.newWorktreeThread(name: "experiment")
        XCTAssertNotNil(worktreeThread, "worktree thread should be created")
        XCTAssertNotEqual(worktreeThread, localThread)

        // The new thread stays in the SAME project but is bound to its own worktree directory.
        XCTAssertEqual(model.selectedThread?.projectID, projectID)
        let binding = model.selectedThread?.worktree
        XCTAssertNotNil(binding)
        XCTAssertEqual(binding?.branch, "")
        let baseBranch = try runGit(["branch", "--show-current"], cwd: repo)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(binding?.base, baseBranch)
        XCTAssertTrue(binding.map(\.isResolvable) ?? false, "worktree dir should exist on disk")
        XCTAssertEqual(model.selectedThread?.title, "Worktree: experiment")
        XCTAssertEqual(
            try String(contentsOf: URL(fileURLWithPath: binding!.path).appendingPathComponent("README.md")),
            "local edit\n"
        )
        XCTAssertEqual(
            try String(contentsOf: URL(fileURLWithPath: binding!.path).appendingPathComponent("notes.txt")),
            "local only\n"
        )

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

    func testSecondWorktreeThreadWithSameNameGetsDistinctManagedPath() throws {
        let repo = try makeGitRepo()
        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: repo, name: "Repo")
        model.selectProject(projectID)

        let first = model.newWorktreeThread(name: "experiment")
        XCTAssertNotNil(first)
        XCTAssertEqual(model.selectedThread?.worktree?.branch, "")
        let firstPath = model.selectedThread?.worktree?.path

        let second = model.newWorktreeThread(name: "experiment")
        XCTAssertNotNil(second, "second worktree thread must be created with a unique managed path")
        XCTAssertNotEqual(second, first)
        let secondBinding = model.selectedThread?.worktree
        XCTAssertEqual(secondBinding?.branch, "")
        XCTAssertTrue(secondBinding.map(\.isResolvable) ?? false, "second worktree dir should exist")

        // The two bound worktrees are distinct directories on disk.
        XCTAssertNotNil(firstPath)
        XCTAssertNotEqual(firstPath, secondBinding?.path)
    }
}
