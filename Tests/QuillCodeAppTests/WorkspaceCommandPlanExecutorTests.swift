import Foundation
import XCTest
@testable import QuillCodeApp

@MainActor
final class WorkspaceCommandPlanExecutorTests: XCTestCase {
    func testExecutorRunsDraftPlanWithoutCommandIDParsing() throws {
        let model = QuillCodeWorkspaceModel()

        XCTAssertTrue(model.runWorkspaceCommandPlan(.setDraft("/remember "), workspaceRoot: try makeTempDirectory()))
        XCTAssertEqual(model.composer.draft, "/remember ")
    }

    func testExecutorRunsStaticActionPlan() throws {
        let model = QuillCodeWorkspaceModel()

        XCTAssertFalse(model.terminal.isVisible)
        XCTAssertTrue(model.runWorkspaceCommandPlan(.action(.toggleTerminal), workspaceRoot: try makeTempDirectory()))
        XCTAssertTrue(model.terminal.isVisible)
    }

    private func makeTempDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("QuillCodeCommandPlanExecutorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
