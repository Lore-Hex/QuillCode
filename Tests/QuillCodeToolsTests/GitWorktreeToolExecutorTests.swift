import XCTest
@testable import QuillCodeTools

final class GitWorktreeToolExecutorTests: XCTestCase {
    func testHandoffTransfersStagedUnstagedAndUntrackedChangesAndCleansSource() throws {
        let fixture = try makeHandoffFixture()
        defer { _ = fixture.git.removeWorktree(cwd: fixture.root, path: fixture.worktreeName, force: true) }
        try addTaskChanges(to: fixture.root)

        let result = fixture.git.handoffWorktree(
            cwd: fixture.root,
            destination: fixture.worktreeName
        )

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertEqual(result.artifacts, [fixture.worktree.path])
        assertTaskChanges(in: fixture.worktree)
        XCTAssertEqual(gitStatus(in: fixture.root), "")
        XCTAssertEqual(
            gitStatus(in: fixture.worktree),
            "M  staged.txt\n M unstaged.txt\n?? notes/task.txt\n"
        )
    }

    func testHandoffRoundTripsChangesBackToSameWorktreeAssociation() throws {
        let fixture = try makeHandoffFixture()
        defer { _ = fixture.git.removeWorktree(cwd: fixture.root, path: fixture.worktreeName, force: true) }
        try addTaskChanges(to: fixture.root)
        let outbound = fixture.git.handoffWorktree(cwd: fixture.root, destination: fixture.worktreeName)
        XCTAssertTrue(outbound.ok, "\(outbound.error ?? "") \(outbound.stderr)")

        let inbound = fixture.git.handoffWorktree(
            cwd: fixture.worktree,
            destination: fixture.root.lastPathComponent
        )

        XCTAssertTrue(inbound.ok, "\(inbound.error ?? "") \(inbound.stderr)")
        XCTAssertEqual(inbound.artifacts, [fixture.root.path])
        assertTaskChanges(in: fixture.root)
        XCTAssertEqual(
            gitStatus(in: fixture.root),
            "M  staged.txt\n M unstaged.txt\n?? notes/task.txt\n"
        )
        XCTAssertEqual(gitStatus(in: fixture.worktree), "")
    }

    func testHandoffAcceptsAnExactTaskSnapshotAlreadyPresentAtDestination() throws {
        let fixture = try makeHandoffFixture()
        defer { _ = fixture.git.removeWorktree(cwd: fixture.root, path: fixture.worktreeName, force: true) }
        try addTaskChanges(to: fixture.root)
        try addTaskChanges(to: fixture.worktree)

        let result = fixture.git.handoffWorktree(
            cwd: fixture.worktree,
            destination: fixture.root.lastPathComponent
        )

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertTrue(result.stdout.contains("already contained the exact task state"), result.stdout)
        assertTaskChanges(in: fixture.root)
        XCTAssertEqual(
            gitStatus(in: fixture.root),
            "M  staged.txt\n M unstaged.txt\n?? notes/task.txt\n"
        )
        XCTAssertEqual(gitStatus(in: fixture.worktree), "")
    }

    func testHandoffRejectsDirtyDestinationWithoutChangingEitherCheckout() throws {
        let fixture = try makeHandoffFixture()
        defer { _ = fixture.git.removeWorktree(cwd: fixture.root, path: fixture.worktreeName, force: true) }
        try addTaskChanges(to: fixture.root)
        try "destination edit\n".write(
            to: fixture.worktree.appendingPathComponent("unstaged.txt"),
            atomically: true,
            encoding: .utf8
        )
        let sourceStatus = gitStatus(in: fixture.root)
        let destinationStatus = gitStatus(in: fixture.worktree)

        let result = fixture.git.handoffWorktree(cwd: fixture.root, destination: fixture.worktreeName)

        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("clean destination checkout") == true, result.error ?? "")
        XCTAssertEqual(gitStatus(in: fixture.root), sourceStatus)
        XCTAssertEqual(gitStatus(in: fixture.worktree), destinationStatus)
        XCTAssertEqual(
            try String(contentsOf: fixture.worktree.appendingPathComponent("unstaged.txt")),
            "destination edit\n"
        )
        assertTaskChanges(in: fixture.root)
    }

    func testHandoffFastForwardsCommittedHistoryAndTransfersLocalChanges() throws {
        let fixture = try makeHandoffFixture()
        defer { _ = fixture.git.removeWorktree(cwd: fixture.root, path: fixture.worktreeName, force: true) }
        try "new commit\n".write(
            to: fixture.root.appendingPathComponent("committed-after-worktree.txt"),
            atomically: true,
            encoding: .utf8
        )
        XCTAssertTrue(fixture.git.stage(cwd: fixture.root, path: "committed-after-worktree.txt").ok)
        XCTAssertTrue(fixture.git.commit(cwd: fixture.root, message: "advance local checkout").ok)
        try addTaskChanges(to: fixture.root)
        let sourceCommit = headCommit(in: fixture.root)

        let result = fixture.git.handoffWorktree(cwd: fixture.root, destination: fixture.worktreeName)

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertTrue(result.stdout.contains("Fast-forwarded committed history"), result.stdout)
        XCTAssertEqual(headCommit(in: fixture.worktree), sourceCommit)
        XCTAssertEqual(
            try String(contentsOf: fixture.worktree.appendingPathComponent("committed-after-worktree.txt")),
            "new commit\n"
        )
        assertTaskChanges(in: fixture.worktree)
        XCTAssertEqual(gitStatus(in: fixture.root), "")
    }

    func testHandoffFastForwardsLocalBranchFromDetachedWorktreeCommit() throws {
        let fixture = try makeHandoffFixture()
        defer { _ = fixture.git.removeWorktree(cwd: fixture.root, path: fixture.worktreeName, force: true) }
        let localBranch = currentBranchName(in: fixture.root)
        try "worktree commit\n".write(
            to: fixture.worktree.appendingPathComponent("worktree-commit.txt"),
            atomically: true,
            encoding: .utf8
        )
        XCTAssertTrue(fixture.git.stage(cwd: fixture.worktree, path: "worktree-commit.txt").ok)
        XCTAssertTrue(fixture.git.commit(cwd: fixture.worktree, message: "commit in detached worktree").ok)
        try addTaskChanges(to: fixture.worktree)
        let worktreeCommit = headCommit(in: fixture.worktree)

        let result = fixture.git.handoffWorktree(
            cwd: fixture.worktree,
            destination: fixture.root.lastPathComponent
        )

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertEqual(headCommit(in: fixture.root), worktreeCommit)
        XCTAssertEqual(currentBranchName(in: fixture.root), localBranch)
        XCTAssertEqual(
            try String(contentsOf: fixture.root.appendingPathComponent("worktree-commit.txt")),
            "worktree commit\n"
        )
        assertTaskChanges(in: fixture.root)
        XCTAssertEqual(gitStatus(in: fixture.worktree), "")
    }

    func testHandoffFastForwardsMultipleCommitsWithoutLocalChanges() throws {
        let fixture = try makeHandoffFixture()
        defer { _ = fixture.git.removeWorktree(cwd: fixture.root, path: fixture.worktreeName, force: true) }
        try commitFile(
            "first.txt",
            contents: "first\n",
            message: "first task commit",
            in: fixture.root,
            git: fixture.git
        )
        try commitFile(
            "second.txt",
            contents: "second\n",
            message: "second task commit",
            in: fixture.root,
            git: fixture.git
        )
        let sourceCommit = headCommit(in: fixture.root)

        let result = fixture.git.handoffWorktree(cwd: fixture.root, destination: fixture.worktreeName)

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertEqual(headCommit(in: fixture.worktree), sourceCommit)
        XCTAssertEqual(
            try String(contentsOf: fixture.worktree.appendingPathComponent("first.txt")),
            "first\n"
        )
        XCTAssertEqual(
            try String(contentsOf: fixture.worktree.appendingPathComponent("second.txt")),
            "second\n"
        )
        XCTAssertEqual(gitStatus(in: fixture.root), "")
        XCTAssertEqual(gitStatus(in: fixture.worktree), "")
    }

    func testHistoryTransferRollbackRestoresOriginalDestinationCommit() throws {
        let fixture = try makeHandoffFixture()
        defer { _ = fixture.git.removeWorktree(cwd: fixture.root, path: fixture.worktreeName, force: true) }
        let originalCommit = headCommit(in: fixture.worktree)
        try commitFile(
            "advanced.txt",
            contents: "advanced\n",
            message: "advance source",
            in: fixture.root,
            git: fixture.git
        )
        let sourceCommit = headCommit(in: fixture.root)
        let transfer = GitWorktreeHandoffHistoryTransfer(runner: GitProcessRunner())
        let transition = GitWorktreeHandoffHistoryTransition.fastForward(
            from: originalCommit,
            to: sourceCommit
        )

        try transfer.apply(transition, at: fixture.worktree)
        XCTAssertEqual(headCommit(in: fixture.worktree), sourceCommit)
        let rollback = transfer.rollback(transition, at: fixture.worktree)

        XCTAssertTrue(rollback.ok, rollback.error ?? "")
        XCTAssertEqual(headCommit(in: fixture.worktree), originalCommit)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: fixture.worktree.appendingPathComponent("advanced.txt").path)
        )
    }

    func testHandoffRejectsDestinationAheadWithoutChangingEitherCheckout() throws {
        let fixture = try makeHandoffFixture()
        defer { _ = fixture.git.removeWorktree(cwd: fixture.root, path: fixture.worktreeName, force: true) }
        try commitFile(
            "destination-only.txt",
            contents: "destination commit\n",
            message: "advance destination",
            in: fixture.worktree,
            git: fixture.git
        )
        let sourceCommit = headCommit(in: fixture.root)
        let destinationCommit = headCommit(in: fixture.worktree)

        let result = fixture.git.handoffWorktree(cwd: fixture.root, destination: fixture.worktreeName)

        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("destination is ahead") == true, result.error ?? "")
        XCTAssertEqual(headCommit(in: fixture.root), sourceCommit)
        XCTAssertEqual(headCommit(in: fixture.worktree), destinationCommit)
    }

    func testHandoffRejectsDivergedCommittedHistoryWithoutMutation() throws {
        let fixture = try makeHandoffFixture()
        defer { _ = fixture.git.removeWorktree(cwd: fixture.root, path: fixture.worktreeName, force: true) }
        try commitFile(
            "source-only.txt",
            contents: "source commit\n",
            message: "advance source",
            in: fixture.root,
            git: fixture.git
        )
        try commitFile(
            "destination-only.txt",
            contents: "destination commit\n",
            message: "advance destination",
            in: fixture.worktree,
            git: fixture.git
        )
        let sourceCommit = headCommit(in: fixture.root)
        let destinationCommit = headCommit(in: fixture.worktree)

        let result = fixture.git.handoffWorktree(cwd: fixture.root, destination: fixture.worktreeName)

        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("have diverged") == true, result.error ?? "")
        XCTAssertEqual(headCommit(in: fixture.root), sourceCommit)
        XCTAssertEqual(headCommit(in: fixture.worktree), destinationCommit)
        XCTAssertEqual(gitStatus(in: fixture.root), "")
        XCTAssertEqual(gitStatus(in: fixture.worktree), "")
    }

    func testHandoffRejectsDirtyDestinationBeforeFastForward() throws {
        let fixture = try makeHandoffFixture()
        defer { _ = fixture.git.removeWorktree(cwd: fixture.root, path: fixture.worktreeName, force: true) }
        try commitFile(
            "source-commit.txt",
            contents: "source commit\n",
            message: "advance source",
            in: fixture.root,
            git: fixture.git
        )
        try "destination edit\n".write(
            to: fixture.worktree.appendingPathComponent("unstaged.txt"),
            atomically: true,
            encoding: .utf8
        )
        let sourceCommit = headCommit(in: fixture.root)
        let destinationCommit = headCommit(in: fixture.worktree)

        let result = fixture.git.handoffWorktree(cwd: fixture.root, destination: fixture.worktreeName)

        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("only into a clean destination") == true, result.error ?? "")
        XCTAssertEqual(headCommit(in: fixture.root), sourceCommit)
        XCTAssertEqual(headCommit(in: fixture.worktree), destinationCommit)
        XCTAssertEqual(
            try String(contentsOf: fixture.worktree.appendingPathComponent("unstaged.txt")),
            "destination edit\n"
        )
    }

    func testHandoffDoesNotMoveIgnoredFiles() throws {
        let fixture = try makeHandoffFixture()
        defer { _ = fixture.git.removeWorktree(cwd: fixture.root, path: fixture.worktreeName, force: true) }
        let ignored = fixture.root.appendingPathComponent("private.secret")
        try "do not transfer\n".write(to: ignored, atomically: true, encoding: .utf8)
        try "transfer me\n".write(
            to: fixture.root.appendingPathComponent("visible.txt"),
            atomically: true,
            encoding: .utf8
        )

        let result = fixture.git.handoffWorktree(cwd: fixture.root, destination: fixture.worktreeName)

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: ignored.path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fixture.worktree.appendingPathComponent("private.secret").path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("visible.txt").path)
        )
        XCTAssertEqual(
            try String(contentsOf: fixture.worktree.appendingPathComponent("visible.txt")),
            "transfer me\n"
        )
        XCTAssertEqual(gitStatus(in: fixture.root), "")
        XCTAssertEqual(gitStatus(in: fixture.worktree), "?? visible.txt\n")
    }

    func testManagedSnapshotFreezesValidatedLocalFileContent() throws {
        let root = try makeTempGitRepoWithInitialCommit()
        let source = root.appendingPathComponent("notes.txt")
        let snapshotRoot = try makeTempDirectory()
        try "captured\n".write(to: source, atomically: true, encoding: .utf8)

        let snapshot = try ManagedWorktreeTransferSnapshot.capture(
            sourceRoot: root,
            temporaryDirectory: snapshotRoot,
            runner: GitProcessRunner()
        )
        try "changed later\n".write(to: source, atomically: true, encoding: .utf8)

        let frozen = try XCTUnwrap(snapshot.files.first { $0.relativePath == "notes.txt" })
        XCTAssertEqual(try String(contentsOf: frozen.snapshotURL), "captured\n")
    }

    func testManagedCreateStartsDetachedAndPreservesLocalChangeState() throws {
        let root = try makeTempGitRepoWithInitialCommit()
        let staged = root.appendingPathComponent("staged.txt")
        let unstaged = root.appendingPathComponent("unstaged.txt")
        try "base staged\n".write(to: staged, atomically: true, encoding: .utf8)
        try "base unstaged\n".write(to: unstaged, atomically: true, encoding: .utf8)
        XCTAssertTrue(GitToolExecutor().stage(cwd: root, path: "staged.txt").ok)
        XCTAssertTrue(GitToolExecutor().stage(cwd: root, path: "unstaged.txt").ok)
        XCTAssertTrue(GitToolExecutor().commit(cwd: root, message: "add transfer fixtures").ok)

        try "staged change\n".write(to: staged, atomically: true, encoding: .utf8)
        XCTAssertTrue(GitToolExecutor().stage(cwd: root, path: "staged.txt").ok)
        try "unstaged change\n".write(to: unstaged, atomically: true, encoding: .utf8)
        try "untracked\n".write(
            to: root.appendingPathComponent("notes.txt"),
            atomically: true,
            encoding: .utf8
        )

        let name = "managed-\(UUID().uuidString)"
        let target = root.deletingLastPathComponent().appendingPathComponent(name)
        let result = GitToolExecutor().createWorktree(cwd: root, path: name, base: "HEAD", managed: true)
        defer { _ = GitToolExecutor().removeWorktree(cwd: root, path: name, force: true) }

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertEqual(currentBranchName(in: target), "", "managed task worktrees start detached")
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("staged.txt")), "staged change\n")
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("unstaged.txt")), "unstaged change\n")
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("notes.txt")), "untracked\n")
        let status = GitToolExecutor().status(cwd: target)
        XCTAssertTrue(status.stdout.contains("M  staged.txt"), status.stdout)
        XCTAssertTrue(status.stdout.contains(" M unstaged.txt"), status.stdout)
        XCTAssertTrue(status.stdout.contains("?? notes.txt"), status.stdout)
    }

    func testCreateBranchHereTurnsDetachedManagedWorktreeIntoOwnedBranch() throws {
        let root = try makeTempGitRepoWithInitialCommit()
        let name = "branch-here-\(UUID().uuidString)"
        let target = root.deletingLastPathComponent().appendingPathComponent(name)
        let git = GitToolExecutor()
        let create = git.createWorktree(cwd: root, path: name, managed: true)
        XCTAssertTrue(create.ok, "\(create.error ?? "") \(create.stderr)")
        defer { _ = git.removeWorktree(cwd: root, path: name, force: true) }
        XCTAssertEqual(currentBranchName(in: target), "")

        let result = git.createWorktreeBranch(cwd: target, branch: "feature/owned-task")

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertEqual(result.artifacts, ["feature/owned-task"])
        XCTAssertEqual(currentBranchName(in: target), "feature/owned-task")
    }

    func testCreateBranchHereRejectsCheckoutThatAlreadyOwnsBranch() throws {
        let root = try makeTempGitRepoWithInitialCommit()
        let before = currentBranchName(in: root)

        let result = GitToolExecutor().createWorktreeBranch(cwd: root, branch: "feature/other")

        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("already owns branch") == true, result.error ?? "")
        XCTAssertEqual(currentBranchName(in: root), before)
    }

    func testCreateBranchHereRejectsUnsafeBranchWithoutChangingDetachedState() throws {
        let root = try makeTempGitRepoWithInitialCommit()
        let name = "unsafe-branch-here-\(UUID().uuidString)"
        let target = root.deletingLastPathComponent().appendingPathComponent(name)
        let git = GitToolExecutor()
        let create = git.createWorktree(cwd: root, path: name, managed: true)
        XCTAssertTrue(create.ok, "\(create.error ?? "") \(create.stderr)")
        defer { _ = git.removeWorktree(cwd: root, path: name, force: true) }

        let result = git.createWorktreeBranch(cwd: target, branch: "feature bad; rm -rf /tmp/nope")

        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("unsupported characters") == true, result.error ?? "")
        XCTAssertEqual(currentBranchName(in: target), "")
    }

    func testManagedCreateCopiesOnlyIncludedIgnoredFilesAndAgentsOverride() throws {
        let root = try makeTempGitRepoWithInitialCommit()
        try ".env\nignored/\nAGENTS.override.md\n".write(
            to: root.appendingPathComponent(".gitignore"),
            atomically: true,
            encoding: .utf8
        )
        try ".env\nignored/config.json\nignored/link\n".write(
            to: root.appendingPathComponent(".worktreeinclude"),
            atomically: true,
            encoding: .utf8
        )
        XCTAssertTrue(GitToolExecutor().stage(cwd: root, path: ".gitignore").ok)
        XCTAssertTrue(GitToolExecutor().stage(cwd: root, path: ".worktreeinclude").ok)
        XCTAssertTrue(GitToolExecutor().commit(cwd: root, message: "configure managed worktrees").ok)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("ignored"),
            withIntermediateDirectories: true
        )
        try "TOKEN=local\n".write(
            to: root.appendingPathComponent(".env"),
            atomically: true,
            encoding: .utf8
        )
        try "{}\n".write(
            to: root.appendingPathComponent("ignored/config.json"),
            atomically: true,
            encoding: .utf8
        )
        try "do not copy\n".write(
            to: root.appendingPathComponent("ignored/not-included.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "local instructions\n".write(
            to: root.appendingPathComponent("AGENTS.override.md"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("ignored/link"),
            withDestinationURL: root.appendingPathComponent(".env")
        )

        let name = "managed-includes-\(UUID().uuidString)"
        let target = root.deletingLastPathComponent().appendingPathComponent(name)
        let result = GitToolExecutor().createWorktree(cwd: root, path: name, managed: true)
        defer { _ = GitToolExecutor().removeWorktree(cwd: root, path: name, force: true) }

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent(".env").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("ignored/config.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("AGENTS.override.md").path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: target.appendingPathComponent("ignored/not-included.txt").path
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent("ignored/link").path))
        XCTAssertTrue(result.stdout.contains("Skipped 1 local symlink"), result.stdout)
    }

    func testManagedCreateRollsBackWhenLocalFileWouldOverwriteBaseContent() throws {
        let root = try makeTempGitRepoWithInitialCommit()
        let collision = root.appendingPathComponent("collision.txt")
        try "tracked in old base\n".write(to: collision, atomically: true, encoding: .utf8)
        XCTAssertTrue(GitToolExecutor().stage(cwd: root, path: "collision.txt").ok)
        XCTAssertTrue(GitToolExecutor().commit(cwd: root, message: "add collision").ok)
        XCTAssertTrue(ShellToolExecutor().run(.init(command: "git tag collision-base", cwd: root)).ok)
        XCTAssertTrue(ShellToolExecutor().run(.init(command: "git rm collision.txt", cwd: root)).ok)
        XCTAssertTrue(GitToolExecutor().commit(cwd: root, message: "remove collision").ok)
        try "untracked current file\n".write(to: collision, atomically: true, encoding: .utf8)

        let name = "managed-rollback-\(UUID().uuidString)"
        let target = root.deletingLastPathComponent().appendingPathComponent(name)
        let result = GitToolExecutor().createWorktree(cwd: root, path: name, base: "collision-base", managed: true)

        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("refused to overwrite") == true, result.error ?? "")
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        XCTAssertFalse(GitToolExecutor().listWorktrees(cwd: root).stdout.contains(target.path))
    }

    func testManagedCreateRejectsBranchCreation() throws {
        let root = try makeTempGitRepoWithInitialCommit()

        let result = GitToolExecutor().createWorktree(
            cwd: root,
            path: "managed-branch",
            branch: "feature/not-detached",
            managed: true
        )

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.error, "Managed worktrees start detached and cannot create a branch.")
    }

    func testCreateBranchHerePromotesDetachedManagedWorktree() throws {
        let root = try makeTempGitRepoWithInitialCommit()
        let worktreeName = "managed-branch-here-\(UUID().uuidString)"
        let worktree = root.deletingLastPathComponent().appendingPathComponent(worktreeName)
        let branch = "feature/managed-\(UUID().uuidString.prefix(8))"
        let git = GitToolExecutor()
        let create = git.createWorktree(cwd: root, path: worktreeName, managed: true)
        XCTAssertTrue(create.ok, create.error ?? create.stderr)
        defer { _ = git.removeWorktree(cwd: root, path: worktreeName, force: true) }

        let promote = git.createWorktreeBranch(cwd: worktree, branch: String(branch))

        XCTAssertTrue(promote.ok, promote.error ?? promote.stderr)
        XCTAssertEqual(currentBranchName(in: worktree), String(branch))
        XCTAssertEqual(promote.artifacts, [String(branch)])
        XCTAssertTrue(promote.stdout.contains("Created branch"), promote.stdout)
    }

    func testCreateBranchHereRejectsExistingAndNonDetachedBranches() throws {
        let root = try makeTempGitRepoWithInitialCommit()
        let worktreeName = "managed-branch-collision-\(UUID().uuidString)"
        let worktree = root.deletingLastPathComponent().appendingPathComponent(worktreeName)
        let git = GitToolExecutor()
        let create = git.createWorktree(cwd: root, path: worktreeName, managed: true)
        XCTAssertTrue(create.ok, create.error ?? create.stderr)
        defer { _ = git.removeWorktree(cwd: root, path: worktreeName, force: true) }

        let existing = git.createWorktreeBranch(cwd: worktree, branch: "main")
        XCTAssertFalse(existing.ok)
        XCTAssertTrue(existing.error?.contains("already checked out") == true, existing.error ?? "")

        let branch = "feature/owned-\(UUID().uuidString.prefix(8))"
        XCTAssertTrue(git.createWorktreeBranch(cwd: worktree, branch: String(branch)).ok)
        let secondPromotion = git.createWorktreeBranch(cwd: worktree, branch: "feature/second")
        XCTAssertFalse(secondPromotion.ok)
        XCTAssertTrue(
            secondPromotion.error?.contains("already owns branch") == true,
            secondPromotion.error ?? ""
        )
    }

    func testCreateBranchHereRejectsExistingUnownedBranch() throws {
        let root = try makeTempGitRepoWithInitialCommit()
        let worktreeName = "managed-existing-branch-\(UUID().uuidString)"
        let worktree = root.deletingLastPathComponent().appendingPathComponent(worktreeName)
        let branch = "feature/existing-\(UUID().uuidString.prefix(8))"
        let git = GitToolExecutor()
        let createBranch = ShellToolExecutor().run(.init(command: "git branch \(branch)", cwd: root))
        XCTAssertTrue(createBranch.ok, createBranch.error ?? createBranch.stderr)
        let createWorktree = git.createWorktree(cwd: root, path: worktreeName, managed: true)
        XCTAssertTrue(createWorktree.ok, createWorktree.error ?? createWorktree.stderr)
        defer { _ = git.removeWorktree(cwd: root, path: worktreeName, force: true) }

        let promote = git.createWorktreeBranch(cwd: worktree, branch: String(branch))

        XCTAssertFalse(promote.ok)
        XCTAssertTrue(promote.error?.contains("branch already exists") == true, promote.error ?? "")
        XCTAssertEqual(currentBranchName(in: worktree), "")
    }

    func testCreateBranchHereRejectsDetachedMainCheckout() throws {
        let root = try makeTempGitRepoWithInitialCommit()
        let detach = ShellToolExecutor().run(.init(command: "git checkout --detach", cwd: root))
        XCTAssertTrue(detach.ok, detach.error ?? detach.stderr)

        let result = GitToolExecutor().createWorktreeBranch(cwd: root, branch: "feature/not-managed")

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.error, "Git worktree path cannot be the main workspace.")
        XCTAssertEqual(currentBranchName(in: root), "")
    }

    func testWorktreePorcelainParserNormalizesLocalBranchNames() {
        let records = GitWorktreePorcelainParser.parse(
            """
            worktree /repo/main
            HEAD 1111111
            branch refs/heads/main

            worktree /repo/task
            HEAD 2222222
            detached

            """
        )

        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0].branch, "main")
        XCTAssertFalse(records[0].isDetached)
        XCTAssertNil(records[1].branch)
        XCTAssertTrue(records[1].isDetached)
    }

    func testCreateListOpenAndRemoveSibling() throws {
        let root = try makeTempGitRepoWithInitialCommit()
        let parent = root.deletingLastPathComponent()
        let worktreeName = "quillcode-worktree-\(UUID().uuidString)"
        let worktree = parent.appendingPathComponent(worktreeName).standardizedFileURL
        let branch = "quillcode-\(UUID().uuidString.prefix(8))"
        let git = GitToolExecutor()

        let create = git.createWorktree(cwd: root, path: worktreeName, branch: String(branch))

        XCTAssertTrue(create.ok, "\(create.error ?? "") \(create.stderr)")
        XCTAssertEqual(create.artifacts, [worktree.path])
        XCTAssertTrue(FileManager.default.fileExists(atPath: worktree.appendingPathComponent(".git").path))

        let list = git.listWorktrees(cwd: root)
        XCTAssertTrue(list.ok, "\(list.error ?? "") \(list.stderr)")
        XCTAssertTrue(list.stdout.contains(worktree.path), list.stdout)
        XCTAssertTrue(list.stdout.contains(String(branch)), list.stdout)

        let open = git.openWorktree(cwd: root, path: worktreeName)

        XCTAssertTrue(open.ok, "\(open.error ?? "") \(open.stderr)")
        XCTAssertEqual(open.artifacts, [worktree.path])
        XCTAssertTrue(open.stdout.contains(worktree.path), open.stdout)

        let remove = git.removeWorktree(cwd: root, path: worktreeName)

        XCTAssertTrue(remove.ok, "\(remove.error ?? "") \(remove.stderr)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: worktree.path))

        let prune = git.pruneWorktrees(cwd: root, dryRun: true, verbose: true)
        XCTAssertTrue(prune.ok, "\(prune.error ?? "") \(prune.stderr)")
    }

    func testManagedCreateOpenAndRemoveUsesConfiguredRootOutsideRepositoryParent() throws {
        let root = try makeTempGitRepoWithInitialCommit()
        let managedRoot = try makeTempDirectory().appendingPathComponent("managed-worktrees")
        let worktree = managedRoot.appendingPathComponent("task-one")
        let git = GitToolExecutor(managedWorktreeRoot: managedRoot)

        let create = git.createWorktree(cwd: root, path: worktree.path, managed: true)
        XCTAssertTrue(create.ok, "\(create.error ?? "") \(create.stderr)")
        XCTAssertEqual(create.artifacts, [worktree.path])

        let open = git.openWorktree(cwd: root, path: worktree.path)
        XCTAssertTrue(open.ok, "\(open.error ?? "") \(open.stderr)")
        XCTAssertEqual(open.artifacts, [worktree.path])

        let remove = git.removeWorktree(cwd: root, path: worktree.path, force: true)
        XCTAssertTrue(remove.ok, "\(remove.error ?? "") \(remove.stderr)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: worktree.path))
    }

    func testConfiguredManagedRootDoesNotAuthorizeOrdinaryWorktreeCreation() throws {
        let root = try makeTempGitRepoWithInitialCommit()
        let managedRoot = try makeTempDirectory().appendingPathComponent("managed-worktrees")
        let git = GitToolExecutor(managedWorktreeRoot: managedRoot)

        let result = git.createWorktree(
            cwd: root,
            path: managedRoot.appendingPathComponent("ordinary").path,
            branch: "feature/ordinary"
        )

        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("outside the workspace") == true, result.error ?? "")
    }

    func testCreateRejectsUnsafePath() throws {
        let root = try makeTempGitRepoWithInitialCommit()

        let result = GitToolExecutor().createWorktree(cwd: root, path: "../outside")

        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("outside the workspace") == true, result.error ?? "")
    }

    func testCreateRejectsWorktreeThroughParentSymlinkEscape() throws {
        let parent = try makeTempDirectory()
        let workspace = parent.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let outside = try makeTempDirectory()
        // A symlink in the workspace's PARENT that points outside it. `escape/wt` is lexically under the
        // parent but resolves into `outside` — the lexical-only check would miss it; the shared
        // WorkspaceBoundary symlink-resolved check must reject it.
        try FileManager.default.createSymbolicLink(
            at: parent.appendingPathComponent("escape"),
            withDestinationURL: outside
        )

        XCTAssertThrowsError(try GitWorktreeToolExecutor.safePath("escape/wt", cwd: workspace)) { error in
            XCTAssertTrue("\(error)".contains("outside the workspace"), "\(error)")
        }
        // A legitimate sibling worktree (no symlink) is still allowed.
        XCTAssertNoThrow(try GitWorktreeToolExecutor.safePath("project-wt", cwd: workspace))
    }

    func testManagedPathRejectsRootSiblingAndSymlinkEscape() throws {
        let workspace = try makeTempDirectory().appendingPathComponent("project")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let managedRoot = try makeTempDirectory().appendingPathComponent("managed")
        try FileManager.default.createDirectory(at: managedRoot, withIntermediateDirectories: true)
        let outside = try makeTempDirectory()
        try FileManager.default.createSymbolicLink(
            at: managedRoot.appendingPathComponent("escape"),
            withDestinationURL: outside
        )

        XCTAssertThrowsError(try GitWorktreeToolExecutor.safeManagedPath(
            managedRoot.path,
            cwd: workspace,
            managedRoot: managedRoot
        ))
        XCTAssertThrowsError(try GitWorktreeToolExecutor.safeManagedPath(
            managedRoot.deletingLastPathComponent().appendingPathComponent("sibling").path,
            cwd: workspace,
            managedRoot: managedRoot
        ))
        XCTAssertThrowsError(try GitWorktreeToolExecutor.safeManagedPath(
            "escape/task",
            cwd: workspace,
            managedRoot: managedRoot
        ))
        XCTAssertEqual(
            try GitWorktreeToolExecutor.safeManagedPath(
                "task",
                cwd: workspace,
                managedRoot: managedRoot
            ),
            managedRoot.appendingPathComponent("task").path
        )
    }

    func testCreateRejectsUnsafeBranchAndBaseNames() throws {
        let root = try makeTempGitRepoWithInitialCommit()
        let git = GitToolExecutor()

        let unsafeBranch = git.createWorktree(cwd: root, path: "safe-worktree", branch: "--bad")
        let unsafeBase = git.createWorktree(cwd: root, path: "safe-worktree", base: "../main")

        XCTAssertFalse(unsafeBranch.ok)
        XCTAssertTrue(unsafeBranch.error?.contains("unsupported characters") == true, unsafeBranch.error ?? "")
        XCTAssertFalse(unsafeBase.ok)
        XCTAssertTrue(unsafeBase.error?.contains("unsupported characters") == true, unsafeBase.error ?? "")
    }

    func testOpenAndRemoveRejectUnregisteredPath() throws {
        let root = try makeTempGitRepoWithInitialCommit()
        let parent = root.deletingLastPathComponent()
        let unrelatedName = "not-a-worktree-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            at: parent.appendingPathComponent(unrelatedName),
            withIntermediateDirectories: true
        )

        let git = GitToolExecutor()
        let open = git.openWorktree(cwd: root, path: unrelatedName)
        let remove = git.removeWorktree(cwd: root, path: unrelatedName, force: true)

        XCTAssertFalse(open.ok)
        XCTAssertTrue(open.error?.contains("not registered") == true, open.error ?? "")
        XCTAssertFalse(remove.ok)
        XCTAssertTrue(remove.error?.contains("not registered") == true, remove.error ?? "")
    }

    private func makeHandoffFixture() throws -> HandoffFixture {
        let root = try makeTempGitRepoWithInitialCommit()
        try "base staged\n".write(
            to: root.appendingPathComponent("staged.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "base unstaged\n".write(
            to: root.appendingPathComponent("unstaged.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "*.secret\n".write(
            to: root.appendingPathComponent(".gitignore"),
            atomically: true,
            encoding: .utf8
        )
        let git = GitToolExecutor()
        XCTAssertTrue(git.stage(cwd: root, path: "staged.txt").ok)
        XCTAssertTrue(git.stage(cwd: root, path: "unstaged.txt").ok)
        XCTAssertTrue(git.stage(cwd: root, path: ".gitignore").ok)
        XCTAssertTrue(git.commit(cwd: root, message: "add handoff fixtures").ok)

        let worktreeName = "handoff-\(UUID().uuidString)"
        let worktree = root.deletingLastPathComponent().appendingPathComponent(worktreeName)
        let create = git.createWorktree(cwd: root, path: worktreeName, managed: true)
        XCTAssertTrue(create.ok, "\(create.error ?? "") \(create.stderr)")
        return HandoffFixture(
            root: root,
            worktree: worktree.standardizedFileURL,
            worktreeName: worktreeName,
            git: git
        )
    }

    private func addTaskChanges(to root: URL) throws {
        try "staged task change\n".write(
            to: root.appendingPathComponent("staged.txt"),
            atomically: true,
            encoding: .utf8
        )
        XCTAssertTrue(GitToolExecutor().stage(cwd: root, path: "staged.txt").ok)
        try "unstaged task change\n".write(
            to: root.appendingPathComponent("unstaged.txt"),
            atomically: true,
            encoding: .utf8
        )
        let notes = root.appendingPathComponent("notes")
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        try "untracked task note\n".write(
            to: notes.appendingPathComponent("task.txt"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func assertTaskChanges(in root: URL, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("staged.txt")),
            "staged task change\n",
            file: file,
            line: line
        )
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("unstaged.txt")),
            "unstaged task change\n",
            file: file,
            line: line
        )
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("notes/task.txt")),
            "untracked task note\n",
            file: file,
            line: line
        )
    }

    private func commitFile(
        _ path: String,
        contents: String,
        message: String,
        in root: URL,
        git: GitToolExecutor
    ) throws {
        try contents.write(
            to: root.appendingPathComponent(path),
            atomically: true,
            encoding: .utf8
        )
        XCTAssertTrue(git.stage(cwd: root, path: path).ok)
        let commit = git.commit(cwd: root, message: message)
        XCTAssertTrue(commit.ok, "\(commit.error ?? "") \(commit.stderr)")
    }

    private func headCommit(in root: URL, file: StaticString = #filePath, line: UInt = #line) -> String {
        let result = ShellToolExecutor().run(.init(command: "git rev-parse HEAD", cwd: root))
        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)", file: file, line: line)
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func gitStatus(in root: URL, file: StaticString = #filePath, line: UInt = #line) -> String {
        let result = ShellToolExecutor().run(.init(
            command: "git status --porcelain=v1 --untracked-files=all",
            cwd: root
        ))
        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)", file: file, line: line)
        return result.stdout
    }
}

private struct HandoffFixture {
    let root: URL
    let worktree: URL
    let worktreeName: String
    let git: GitToolExecutor
}
