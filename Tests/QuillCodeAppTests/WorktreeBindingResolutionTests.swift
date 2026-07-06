import XCTest
import Foundation
import QuillCodeCore
@testable import QuillCodeApp

@MainActor
final class WorktreeBindingResolutionTests: XCTestCase {
    private func tempDir(_ tag: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wtbind-\(tag)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testUsesProjectRootWhenNoBinding() throws {
        let model = QuillCodeWorkspaceModel()
        let project = try tempDir("proj")
        let projectID = model.addProject(path: project, name: "Demo")
        model.selectProject(projectID)
        _ = model.newChat(projectID: projectID)
        XCTAssertEqual(model.activeWorkspaceRoot?.standardizedFileURL, project.standardizedFileURL)
    }

    func testUsesBindingWhenSetAndExists() throws {
        let model = QuillCodeWorkspaceModel()
        let project = try tempDir("proj")
        let worktree = try tempDir("wt")
        let projectID = model.addProject(path: project, name: "Demo")
        model.selectProject(projectID)
        _ = model.newChat(projectID: projectID)

        model.bindSelectedThreadToWorktree(path: worktree.path, branch: "feature/x", base: "main")
        XCTAssertEqual(model.activeWorkspaceRoot?.standardizedFileURL, worktree.standardizedFileURL)
        XCTAssertEqual(model.selectedThread?.worktree?.branch, "feature/x")
        XCTAssertEqual(model.selectedThread?.worktree?.base, "main")
    }

    func testFallsBackToProjectRootWhenBindingPathMissing() throws {
        let model = QuillCodeWorkspaceModel()
        let project = try tempDir("proj")
        let projectID = model.addProject(path: project, name: "Demo")
        model.selectProject(projectID)
        _ = model.newChat(projectID: projectID)

        // A dangling binding (worktree removed) must not point the run at a missing dir.
        model.bindSelectedThreadToWorktree(path: project.path + "-gone", branch: "x")
        XCTAssertEqual(model.activeWorkspaceRoot?.standardizedFileURL, project.standardizedFileURL)
    }

    func testBindBumpsUpdatedAtAndPersists() throws {
        let model = QuillCodeWorkspaceModel()
        let project = try tempDir("proj")
        let worktree = try tempDir("wt")
        let projectID = model.addProject(path: project, name: "Demo")
        model.selectProject(projectID)
        _ = model.newChat(projectID: projectID)
        let before = model.selectedThread?.updatedAt

        model.bindSelectedThreadToWorktree(path: worktree.path, branch: "b")
        XCTAssertNotNil(model.selectedThread?.worktree)
        if let before, let after = model.selectedThread?.updatedAt {
            XCTAssertGreaterThanOrEqual(after, before)
        }
    }

    func testTwoThreadsSameProjectResolveDisjointRoots() throws {
        // The isolation proof: two threads on ONE project resolve to DIFFERENT run roots — a bound
        // thread to its worktree, an unbound one to the shared project root.
        let model = QuillCodeWorkspaceModel()
        let project = try tempDir("proj")
        let worktree = try tempDir("wt")
        let projectID = model.addProject(path: project, name: "Demo")
        model.selectProject(projectID)

        let boundThread = model.newChat(projectID: projectID)
        model.bindSelectedThreadToWorktree(path: worktree.path, branch: "feature/x")
        let unboundThread = model.newChat(projectID: projectID)

        model.selectThread(boundThread)
        XCTAssertEqual(model.activeWorkspaceRoot?.standardizedFileURL, worktree.standardizedFileURL)
        model.selectThread(unboundThread)
        XCTAssertEqual(model.activeWorkspaceRoot?.standardizedFileURL, project.standardizedFileURL)
    }
}
