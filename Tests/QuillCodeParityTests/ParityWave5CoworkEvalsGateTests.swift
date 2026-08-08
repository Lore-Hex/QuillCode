import Foundation
import XCTest

final class ParityWave5CoworkEvalsGateTests: XCTestCase {
    func testWave5DesktopEvalPinsModelCountAndControllerPath() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let script = try String(
            contentsOf: root.appendingPathComponent("scripts/wave5-cowork-evals.py"),
            encoding: .utf8
        )
        let runner = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/quill-code-desktop/QuillCodeDesktopCoworkEvalRunner.swift"
            ),
            encoding: .utf8
        )
        let app = try String(
            contentsOf: root.appendingPathComponent("Sources/quill-code-desktop/QuillCodeDesktopApp.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(script.contains(#"EXACT_MODEL = "deepseek/deepseek-v4-flash-0731""#))
        XCTAssertTrue(script.contains("EXPECTED_IDS = set(range(211, 311))"))
        XCTAssertTrue(script.contains("Paid invocation fuse exceeded 100 cases"))
        XCTAssertTrue(script.contains("--cowork-eval"))
        XCTAssertTrue(runner.contains("controller.send()"))
        XCTAssertTrue(runner.contains("controller.openBrowserPreview()"))
        XCTAssertTrue(app.contains("QuillCodeDesktopCoworkEvalRequest(arguments: CommandLine.arguments)"))
    }
}
