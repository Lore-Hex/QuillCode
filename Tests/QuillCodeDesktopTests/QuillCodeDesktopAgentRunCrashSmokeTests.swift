import XCTest
@testable import quill_code_desktop

final class QuillCodeDesktopAgentRunCrashSmokeTests: XCTestCase {
    func testRequestRequiresFlagAndParsesPhaseAndStateRoot() throws {
        XCTAssertNil(QuillCodeDesktopAgentRunCrashSmokeRequest(arguments: ["Quill Cowork"]))

        let request = try XCTUnwrap(QuillCodeDesktopAgentRunCrashSmokeRequest(arguments: [
            "Quill Cowork",
            "--agent-run-crash-smoke",
            "--agent-run-crash-phase",
            "verify",
            "--agent-run-crash-state-root",
            "/tmp/quill-agent-run-crash"
        ]))

        XCTAssertEqual(request.phase, "verify")
        XCTAssertEqual(request.stateRootPath, "/tmp/quill-agent-run-crash")
        let root = QuillCodeDesktopAgentRunCrashSmokeWorkspaceRoot(request: request)
        XCTAssertEqual(root.root.path, "/tmp/quill-agent-run-crash")
        XCTAssertEqual(root.appState.lastPathComponent, "app-state")
        XCTAssertEqual(root.workspace.lastPathComponent, "workspace")
    }
}
