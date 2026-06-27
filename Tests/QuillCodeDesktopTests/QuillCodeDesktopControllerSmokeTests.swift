import XCTest
import QuillCodeApp
import QuillCodeCore
import QuillCodePersistence
@testable import quill_code_desktop

@MainActor
final class QuillCodeDesktopControllerSmokeTests: XCTestCase {
    func testDesktopControllerSendPathCoversRealWorldActionPromptFamily() async throws {
        let workspaceRoot = try makeTempDirectory()
        let downloadSource = workspaceRoot.appendingPathComponent("source.html")
        try "<!doctype html><title>QuillCode desktop smoke</title>\n"
            .write(to: downloadSource, atomically: true, encoding: .utf8)

        let cases = [
            DesktopRealWorldSmokeCase(
                prompt: "whoami?",
                toolName: ToolDefinition.shellRun.name,
                inputContains: ["\"cmd\":\"whoami\""],
                answerContains: "You are `",
                sideEffect: nil
            ),
            DesktopRealWorldSmokeCase(
                prompt: "How much hd?",
                toolName: ToolDefinition.shellRun.name,
                inputContains: ["df -h / /Quill"],
                answerContains: "Disk usage:",
                sideEffect: nil
            ),
            DesktopRealWorldSmokeCase(
                prompt: "Do you have openclaw?",
                toolName: ToolDefinition.shellRun.name,
                inputContains: ["command -v openclaw"],
                answerContains: "openclaw is",
                sideEffect: nil
            ),
            DesktopRealWorldSmokeCase(
                prompt: "Can you write a file that says \"hello world\"",
                toolName: ToolDefinition.fileWrite.name,
                inputContains: ["\"path\":\"hello.txt\"", "hello world"],
                answerContains: "Wrote `hello.txt`.",
                sideEffect: .fileContains(path: "hello.txt", text: "hello world")
            ),
            DesktopRealWorldSmokeCase(
                prompt: "Download \(downloadSource.absoluteString) into `downloads/example.html` in this workspace.",
                toolName: ToolDefinition.shellRun.name,
                inputContains: [
                    "mkdir -p 'downloads'",
                    "--output 'downloads/example.html'",
                    downloadSource.absoluteString
                ],
                answerContains: "Downloaded to `downloads/example.html`.",
                sideEffect: .fileContains(path: "downloads/example.html", text: "QuillCode desktop smoke")
            )
        ]

        for testCase in cases {
            let controller = try makeController(workspaceRoot: workspaceRoot)
            controller.draft = testCase.prompt
            let previousTimelineCount = controller.surface.transcript.timelineItems.count
            controller.send()

            try await waitForDesktopRun(
                controller,
                previousTimelineCount: previousTimelineCount,
                expectedAnswer: testCase.answerContains
            )

            let surface = controller.surface
            XCTAssertFalse(surface.composer.isSending, testCase.prompt)
            XCTAssertNil(surface.lastError, testCase.prompt)

            let timeline = surface.transcript.timelineItems
            let latestKinds = Array(timeline.suffix(3).map(\.kind))
            XCTAssertEqual(
                latestKinds,
                [
                    TranscriptTimelineItemKind.message,
                    TranscriptTimelineItemKind.toolCard,
                    TranscriptTimelineItemKind.message
                ],
                testCase.prompt
            )

            let latestMessages = Array(surface.transcript.messages.suffix(2))
            XCTAssertEqual(latestMessages.first?.text, testCase.prompt)
            let answer = try XCTUnwrap(latestMessages.last?.text, testCase.prompt)
            XCTAssertTrue(answer.contains(testCase.answerContains), "\(testCase.prompt): \(answer)")
            XCTAssertFalse(
                answer.range(
                    of: #"I'?ll (run|check|do|download|create|write)"#,
                    options: String.CompareOptions.regularExpression
                ) != nil,
                testCase.prompt
            )
            XCTAssertFalse(answer.localizedCaseInsensitiveContains("No shell command was specified"), testCase.prompt)

            let card = try XCTUnwrap(surface.transcript.toolCards.last, testCase.prompt)
            XCTAssertEqual(card.title, testCase.toolName, testCase.prompt)
            XCTAssertEqual(card.status, .done, testCase.prompt)
            XCTAssertNotEqual(card.inputJSON, "{}", testCase.prompt)
            let normalizedInputJSON = normalizeToolInputJSON(card.inputJSON)
            for expectedInput in testCase.inputContains {
                let normalizedExpectedInput = expectedInput.replacingOccurrences(of: " ", with: "")
                XCTAssertTrue(
                    normalizedInputJSON.contains(normalizedExpectedInput),
                    "\(testCase.prompt): \(expectedInput)"
                )
            }

            try assertSideEffect(testCase.sideEffect, workspaceRoot: workspaceRoot, label: testCase.prompt)
        }
    }

    private func makeController(workspaceRoot: URL) throws -> QuillCodeDesktopController {
        let stateRoot = try makeTempDirectory().appendingPathComponent("state", isDirectory: true)
        let paths = QuillCodePaths(home: stateRoot)
        let runtimeFactory = QuillCodeRuntimeFactory(
            paths: paths,
            environment: ["QUILLCODE_USE_MOCK_LLM": "1"]
        )
        let bootstrap = QuillCodeWorkspaceBootstrap(paths: paths, runtimeFactory: runtimeFactory)
        return QuillCodeDesktopController(
            bootstrap: bootstrap,
            browserPageFetcher: URLSessionBrowserPageFetcher(),
            browserLiveDOMCapturer: nil,
            browserSessionPresenter: NoopDesktopBrowserSessionPresenter(),
            automationNotifier: NoopAutomationNotifier(),
            workspaceRoot: workspaceRoot
        )
    }

    private func waitForDesktopRun(
        _ controller: QuillCodeDesktopController,
        previousTimelineCount: Int,
        expectedAnswer: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        for _ in 0..<300 {
            let timelineCount = controller.surface.transcript.timelineItems.count
            let latestAnswer = controller.surface.transcript.messages.last?.text ?? ""
            if !controller.surface.composer.isSending,
               timelineCount >= previousTimelineCount + 3,
               latestAnswer.contains(expectedAnswer) {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Desktop send did not complete with expected answer: \(expectedAnswer)", file: file, line: line)
    }

    private func assertSideEffect(
        _ sideEffect: DesktopRealWorldSmokeSideEffect?,
        workspaceRoot: URL,
        label: String
    ) throws {
        switch sideEffect {
        case .fileContains(let path, let text):
            let url = workspaceRoot.appendingPathComponent(path)
            let contents = try String(contentsOf: url, encoding: .utf8)
            XCTAssertTrue(contents.contains(text), "\(label): \(url.path)")
        case .none:
            break
        }
    }

    private func normalizeToolInputJSON(_ inputJSON: String?) -> String {
        (inputJSON ?? "")
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillCodeDesktopTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}

private struct DesktopRealWorldSmokeCase {
    var prompt: String
    var toolName: String
    var inputContains: [String]
    var answerContains: String
    var sideEffect: DesktopRealWorldSmokeSideEffect?
}

private enum DesktopRealWorldSmokeSideEffect {
    case fileContains(path: String, text: String)
}

@MainActor
private final class NoopDesktopBrowserSessionPresenter: DesktopBrowserSessionPresenting {
    func openSession(url _: URL) {}
}

private struct NoopAutomationNotifier: QuillCodeAutomationNotifying {
    func deliver(_ report: AutomationRunReport) {}
}
