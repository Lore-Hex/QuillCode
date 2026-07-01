import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp
@testable import quill_code_desktop

@MainActor
final class QuillCodeDesktopSourceOpenerTests: XCTestCase {
    func testWorkspaceCommandOpensActivitySourceAtLineThroughNativeOpener() throws {
        let root = try makeTempDirectory()
        let fileURL = root.appendingPathComponent("AGENTS.md")
        try "One\nTwo\n".write(to: fileURL, atomically: true, encoding: .utf8)
        let opener = RecordingSourceOpener(result: true)
        let coordinator = QuillCodeDesktopWorkspaceActionCoordinator(sourceOpener: opener)

        XCTAssertTrue(coordinator.runWorkspaceCommand(
            "activity-source-open-line:2:AGENTS.md",
            model: QuillCodeWorkspaceModel(),
            fallbackWorkspaceRoot: root
        ))

        XCTAssertEqual(opener.requests, [
            QuillCodeDesktopSourceOpenRequest(fileURL: fileURL.standardizedFileURL, lineNumber: 2)
        ])
    }

    func testWorkspaceCommandFallsBackWhenNativeSourceOpenFails() throws {
        let root = try makeTempDirectory()
        try "Use Swift patterns.\n".write(
            to: root.appendingPathComponent("AGENTS.md"),
            atomically: true,
            encoding: .utf8
        )
        let thread = ChatThread(
            title: "Inspect source",
            messages: [.init(role: .user, content: "what rules apply?")],
            instructions: [
                ProjectInstruction(
                    path: "AGENTS.md",
                    title: "AGENTS.md",
                    content: "Use Swift patterns.",
                    byteCount: 19
                )
            ]
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))
        let opener = RecordingSourceOpener(result: false)
        let coordinator = QuillCodeDesktopWorkspaceActionCoordinator(sourceOpener: opener)

        XCTAssertTrue(coordinator.runWorkspaceCommand(
            "activity-source-open-line:1:AGENTS.md",
            model: model,
            fallbackWorkspaceRoot: root
        ))

        XCTAssertEqual(opener.requests.count, 1)
        let selectedThread = try XCTUnwrap(model.selectedThread)
        let card = try XCTUnwrap(WorkspaceTranscriptSurfaceBuilder(thread: selectedThread).toolCards().last)
        XCTAssertEqual(card.title, ToolDefinition.fileRead.name)
        XCTAssertEqual(card.inputJSON, ToolArguments.json([
            "limit": 120,
            "offset": 1,
            "path": "AGENTS.md"
        ]))
    }

    func testWorkspaceCommandDoesNotNativeOpenEscapedSourcePath() throws {
        let root = try makeTempDirectory()
        let outside = root.deletingLastPathComponent().appendingPathComponent("outside-agents.md")
        try "outside\n".write(to: outside, atomically: true, encoding: .utf8)
        let thread = ChatThread(title: "Inspect source", messages: [.init(role: .user, content: "open source")])
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))
        let opener = RecordingSourceOpener(result: true)
        let coordinator = QuillCodeDesktopWorkspaceActionCoordinator(sourceOpener: opener)

        XCTAssertTrue(coordinator.runWorkspaceCommand(
            "activity-source-open-line:1:../outside-agents.md",
            model: model,
            fallbackWorkspaceRoot: root
        ))

        XCTAssertTrue(opener.requests.isEmpty)
    }

    private func makeTempDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-desktop-source-opener-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

@MainActor
private final class RecordingSourceOpener: QuillCodeDesktopSourceOpening {
    var requests: [QuillCodeDesktopSourceOpenRequest] = []
    private let result: Bool

    init(result: Bool) {
        self.result = result
    }

    func openSource(_ request: QuillCodeDesktopSourceOpenRequest) -> Bool {
        requests.append(request)
        return result
    }
}
