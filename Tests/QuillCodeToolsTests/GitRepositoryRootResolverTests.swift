import Foundation
import XCTest
@testable import QuillCodeTools

final class GitRepositoryRootResolverTests: XCTestCase {
    func testNormalCheckoutUsesItsOwnRootForConfiguration() throws {
        let root = try temporaryDirectory()
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        let nested = root.appendingPathComponent("Sources/Feature", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        let roots = try XCTUnwrap(GitRepositoryRootResolver.resolve(containing: nested))

        XCTAssertEqual(roots.checkout.path, root.path)
        XCTAssertEqual(roots.configuration.path, root.path)
    }

    func testLinkedWorktreeUsesPrimaryCheckoutForConfiguration() throws {
        let parent = try temporaryDirectory()
        let primary = parent.appendingPathComponent("primary", isDirectory: true)
        let worktree = parent.appendingPathComponent("feature", isDirectory: true)
        let worktreeGitDirectory = primary
            .appendingPathComponent(".git/worktrees/feature", isDirectory: true)
        try FileManager.default.createDirectory(
            at: worktreeGitDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        try "gitdir: ../primary/.git/worktrees/feature\n".write(
            to: worktree.appendingPathComponent(".git"),
            atomically: true,
            encoding: .utf8
        )
        try "../..\n".write(
            to: worktreeGitDirectory.appendingPathComponent("commondir"),
            atomically: true,
            encoding: .utf8
        )

        let roots = try XCTUnwrap(GitRepositoryRootResolver.resolve(containing: worktree))

        XCTAssertEqual(roots.checkout.path, worktree.path)
        XCTAssertEqual(roots.configuration.path, primary.path)
    }

    func testMalformedLinkedMarkerFallsBackToCheckout() throws {
        let root = try temporaryDirectory()
        try "not a gitdir".write(
            to: root.appendingPathComponent(".git"),
            atomically: true,
            encoding: .utf8
        )

        let roots = try XCTUnwrap(GitRepositoryRootResolver.resolve(containing: root))

        XCTAssertEqual(roots.checkout.path, root.path)
        XCTAssertEqual(roots.configuration.path, root.path)
    }

    func testDirectoryOutsideRepositoryReturnsNil() throws {
        XCTAssertNil(GitRepositoryRootResolver.resolve(containing: try temporaryDirectory()))
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitRepositoryRootResolverTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
}
