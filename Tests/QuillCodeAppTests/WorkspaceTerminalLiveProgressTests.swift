import Foundation
import XCTest
@testable import QuillCodeApp

@MainActor
final class WorkspaceTerminalLiveProgressTests: XCTestCase {
    func testRunPublishesLiveOutputBeforeCompletion() async throws {
        let root = try makeQuillCodeTestDirectory()
        let model = QuillCodeWorkspaceModel()
        var samples: [(status: TerminalCommandStatus?, stdout: String)] = []

        await model.runTerminalCommand(
            "printf live-start; sleep 0.2; printf live-end",
            workspaceRoot: root,
            onStateChange: {
                samples.append((
                    status: model.terminal.entries.last?.status,
                    stdout: model.surface().terminal.entries.last?.stdout ?? ""
                ))
            }
        )

        XCTAssertTrue(samples.contains { sample in
            sample.status == .running
                && sample.stdout.contains("live-start")
                && !sample.stdout.contains("live-end")
        }, "Expected at least one running-state projection after the first output chunk: \(samples)")
        XCTAssertEqual(model.terminal.entries.last?.status, .done)
        XCTAssertEqual(model.terminal.entries.last?.stdout, "live-startlive-end")
    }
}
