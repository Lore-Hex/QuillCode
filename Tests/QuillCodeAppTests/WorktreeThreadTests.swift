import XCTest
import Foundation
import QuillCodeCore
import QuillCodePersistence
import QuillCodeTools
@testable import QuillCodeApp

// MARK: - Unit: the pure planner

final class WorktreeThreadPlannerTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/work/MyRepo")
    private let managedRoot = URL(fileURLWithPath: "/managed/worktrees")

    func testSlugifies() {
        XCTAssertEqual(WorktreeThreadPlanner.slug(from: "Add Login Flow!"), "add-login-flow")
        XCTAssertEqual(WorktreeThreadPlanner.slug(from: "  spaced  out  "), "spaced-out")
        XCTAssertNil(WorktreeThreadPlanner.slug(from: "  !!!  "))
        XCTAssertNil(WorktreeThreadPlanner.slug(from: nil))
    }

    func testManagedRequestUsesConfiguredRoot() {
        let plan = WorktreeThreadPlanner.plan(
            projectRoot: root,
            managedRoot: managedRoot,
            baseBranch: "main",
            name: "Try It",
            identifier: "ABCDEF12-3456"
        )
        XCTAssertEqual(plan.request.branch, "")
        XCTAssertEqual(plan.request.base, "main")
        XCTAssertTrue(plan.request.managed)
        XCTAssertEqual(plan.request.path, "/managed/worktrees/MyRepo-try-it-abcdef12")
        XCTAssertEqual(plan.title, "Worktree: try-it")
    }

    func testDefaultNameWhenNil() {
        let plan = WorktreeThreadPlanner.plan(
            projectRoot: root,
            managedRoot: managedRoot,
            baseBranch: "main",
            name: nil,
            identifier: "12345678"
        )
        XCTAssertEqual(plan.request.branch, "")
        XCTAssertEqual(plan.request.path, "/managed/worktrees/MyRepo-work-12345678")
        XCTAssertEqual(plan.title, "Worktree: work")
    }

    func testIdentifiersKeepSameNamePlansDistinct() {
        let first = WorktreeThreadPlanner.plan(
            projectRoot: root,
            managedRoot: managedRoot,
            baseBranch: "main",
            name: "work",
            identifier: "11111111"
        )
        let second = WorktreeThreadPlanner.plan(
            projectRoot: root,
            managedRoot: managedRoot,
            baseBranch: "main",
            name: "work",
            identifier: "22222222"
        )
        XCTAssertNotEqual(first.request.path, second.request.path)
    }
}

// MARK: - Functional/integration: newWorktreeThread through the model against a real git repo

@MainActor
final class WorktreeThreadModelTests: XCTestCase {
    private func makeModel() -> QuillCodeWorkspaceModel {
        QuillCodeWorkspaceModel(
            managedWorktreeDefaultRoot: FileManager.default.temporaryDirectory
                .appendingPathComponent("quillcode-worktree-tests")
                .appendingPathComponent(UUID().uuidString)
        )
    }

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
        let model = makeModel()
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
        let model = makeModel()
        XCTAssertNil(model.newWorktreeThread(name: "x"), "no selected project → nil")
    }

    func testSecondWorktreeThreadWithSameNameGetsDistinctManagedPath() throws {
        let repo = try makeGitRepo()
        let model = makeModel()
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

    func testRetentionSnapshotsOldestWorktreeAndKeepsItRestorable() throws {
        let repo = try makeGitRepo()
        let dataRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("wt-retention-\(UUID().uuidString)")
        let managedRoot = dataRoot.appendingPathComponent("worktrees")
        let snapshotRoot = dataRoot.appendingPathComponent("snapshots")
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                config: AppConfig(managedWorktreeRetentionLimit: 1)
            ),
            threadStore: JSONThreadStore(directory: dataRoot.appendingPathComponent("threads")),
            worktreeSnapshotStore: ManagedWorktreeSnapshotStore(directory: snapshotRoot),
            managedWorktreeDefaultRoot: managedRoot
        )
        let projectID = model.addProject(path: repo, name: "Repo")
        model.selectProject(projectID)

        let oldestID = try XCTUnwrap(model.newWorktreeThread(name: "oldest"))
        let oldestPath = try XCTUnwrap(model.selectedThread?.worktree?.path)
        try "recover me\n".write(
            to: URL(fileURLWithPath: oldestPath).appendingPathComponent("recovery.txt"),
            atomically: true,
            encoding: .utf8
        )

        let newestID = try XCTUnwrap(model.newWorktreeThread(name: "newest"))
        let newestPath = try XCTUnwrap(model.selectedThread?.worktree?.path)
        defer {
            for path in [oldestPath, newestPath] where FileManager.default.fileExists(atPath: path) {
                _ = GitToolExecutor().removeWorktree(
                    cwd: repo,
                    path: path,
                    force: true
                )
            }
        }

        XCTAssertNotEqual(oldestID, newestID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldestPath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newestPath))
        XCTAssertNotNil(model.root.threads.first(where: { $0.id == oldestID })?.worktree?.snapshot)

        XCTAssertTrue(model.restoreManagedWorktree(threadID: oldestID))
        XCTAssertEqual(
            try String(contentsOf: URL(fileURLWithPath: oldestPath).appendingPathComponent("recovery.txt")),
            "recover me\n"
        )
    }

    func testCustomManagedRootOverridesDefaultRoot() throws {
        let repo = try makeGitRepo()
        let defaultRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("wt-default-\(UUID().uuidString)")
        let customRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("wt-custom-\(UUID().uuidString)")
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(config: AppConfig(managedWorktreeRoot: customRoot.path)),
            managedWorktreeDefaultRoot: defaultRoot
        )
        let projectID = model.addProject(path: repo, name: "Repo")
        model.selectProject(projectID)

        _ = try XCTUnwrap(model.newWorktreeThread(name: "custom"))
        let path = try XCTUnwrap(model.selectedThread?.worktree?.path)
        defer {
            _ = GitToolExecutor().removeWorktree(
                cwd: repo,
                path: path,
                force: true
            )
        }

        XCTAssertTrue(URL(fileURLWithPath: path).standardizedFileURL.path.hasPrefix(customRoot.path + "/"))
        XCTAssertFalse(path.hasPrefix(defaultRoot.path + "/"))
    }

    func testManagedTaskHandsOffToLocalAndBackWithoutChangingItsThreadOrWorktree() throws {
        let repo = try makeGitRepo()
        let model = makeModel()
        let projectID = model.addProject(path: repo, name: "Repo")
        model.selectProject(projectID)
        try "task edit\n".write(
            to: repo.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        try "task note\n".write(
            to: repo.appendingPathComponent("notes.txt"),
            atomically: true,
            encoding: .utf8
        )
        let threadID = try XCTUnwrap(model.newWorktreeThread(name: "handoff"))
        let worktreePath = try XCTUnwrap(model.selectedThread?.worktree?.path)
        let worktree = URL(fileURLWithPath: worktreePath)
        defer {
            _ = GitToolExecutor().removeWorktree(
                cwd: repo,
                path: worktree.path,
                force: true
            )
        }

        XCTAssertTrue(model.handoffSelectedThread())
        XCTAssertEqual(model.selectedThread?.id, threadID)
        XCTAssertEqual(model.selectedThread?.worktree?.path, worktreePath)
        XCTAssertEqual(model.selectedThread?.worktree?.location, .local)
        XCTAssertEqual(model.activeWorkspaceRoot?.standardizedFileURL, repo.standardizedFileURL)
        XCTAssertEqual(
            try runGit(["status", "--porcelain=v1", "--untracked-files=all"], cwd: worktree),
            ""
        )

        XCTAssertTrue(model.handoffSelectedThread())
        XCTAssertEqual(model.selectedThread?.id, threadID)
        XCTAssertEqual(model.selectedThread?.worktree?.path, worktreePath)
        XCTAssertEqual(model.selectedThread?.worktree?.location, .worktree)
        XCTAssertEqual(model.activeWorkspaceRoot?.standardizedFileURL, worktree.standardizedFileURL)
        XCTAssertEqual(
            try runGit(["status", "--porcelain=v1", "--untracked-files=all"], cwd: repo),
            ""
        )
        XCTAssertEqual(
            try String(contentsOf: worktree.appendingPathComponent("README.md")),
            "task edit\n"
        )
        XCTAssertEqual(
            try String(contentsOf: worktree.appendingPathComponent("notes.txt")),
            "task note\n"
        )
    }

    func testCreateBranchHereKeepsTaskInWorktreeAndPersistsOwnership() throws {
        let repo = try makeGitRepo()
        let model = makeModel()
        let projectID = model.addProject(path: repo, name: "Repo")
        model.selectProject(projectID)
        let threadID = try XCTUnwrap(model.newWorktreeThread(name: "owned"))
        let worktreePath = try XCTUnwrap(model.selectedThread?.worktree?.path)
        let worktree = URL(fileURLWithPath: worktreePath)
        defer { _ = GitToolExecutor().removeWorktree(cwd: repo, path: worktree.path, force: true) }

        XCTAssertTrue(model.createBranchHere(.init(branch: "feature/owned-task")))

        XCTAssertEqual(model.selectedThread?.id, threadID)
        XCTAssertEqual(model.selectedThread?.worktree?.path, worktreePath)
        XCTAssertEqual(model.selectedThread?.worktree?.location, .worktree)
        XCTAssertEqual(model.selectedThread?.worktree?.branch, "feature/owned-task")
        XCTAssertEqual(model.activeWorkspaceRoot?.standardizedFileURL, worktree.standardizedFileURL)
        XCTAssertEqual(
            try runGit(["branch", "--show-current"], cwd: worktree)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            "feature/owned-task"
        )
        XCTAssertFalse(model.handoffSelectedThread(), "branch-owned worktrees cannot hand off")
    }

    func testCreateBranchHereFailureDoesNotMutateDetachedBinding() throws {
        let repo = try makeGitRepo()
        let model = makeModel()
        let projectID = model.addProject(path: repo, name: "Repo")
        model.selectProject(projectID)
        _ = try XCTUnwrap(model.newWorktreeThread(name: "invalid"))
        let worktree = URL(fileURLWithPath: try XCTUnwrap(model.selectedThread?.worktree?.path))
        defer { _ = GitToolExecutor().removeWorktree(cwd: repo, path: worktree.path, force: true) }

        XCTAssertFalse(model.createBranchHere(.init(branch: "invalid branch; nope")))

        XCTAssertEqual(model.selectedThread?.worktree?.branch, "")
        XCTAssertEqual(
            try runGit(["branch", "--show-current"], cwd: worktree)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            ""
        )
    }
}
