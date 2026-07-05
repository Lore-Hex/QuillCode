import XCTest
import QuillCodeApp
@testable import quill_code_desktop

final class ChromiumBrowserLiveDOMCapturerTests: XCTestCase {
    func testExecutableLocatorFindsPathCandidate() throws {
        let root = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("google-chrome-stable")
        try "#!/bin/sh\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let locator = BrowserProcessExecutableLocator(
            candidates: ["chromium", "google-chrome-stable"],
            environment: ["PATH": root.path]
        )

        XCTAssertEqual(locator.browserExecutable(), executable.path)
    }

    func testExecutableLocatorAcceptsAbsoluteCandidate() throws {
        let root = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("chromium")
        try "#!/bin/sh\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let locator = BrowserProcessExecutableLocator(
            candidates: [executable.path],
            environment: ["PATH": ""]
        )

        XCTAssertEqual(locator.browserExecutable(), executable.path)
    }

    func testCapturerBuildsHeadlessInvocationAndParsesRenderedDOM() async throws {
        let runner = RecordingBrowserProcessRunner(result: .success(BrowserProcessRenderResult(
            stdout: """
            <!doctype html>
            <html>
              <head><title>Rendered app</title></head>
              <body>
                <h1>Dashboard</h1>
                <button>Launch</button>
                <input aria-label="Search everything">
                <p>Dynamic total: 42</p>
              </body>
            </html>
            """,
            stderr: "",
            exitCode: 0
        )))
        let capturer = ChromiumBrowserLiveDOMCapturer(
            executableLocator: StaticBrowserExecutableLocator(executable: "/usr/bin/chromium"),
            processRunner: runner,
            timeout: 4,
            virtualTimeBudgetMilliseconds: 1_500,
            environment: ["PATH": "/usr/bin"],
            allowNoSandbox: true
        )

        let snapshot = try await capturer.captureLiveDOM(for: URL(string: "https://example.test/app")!)
        let recordedInvocation = await runner.firstInvocation()
        let invocation = try XCTUnwrap(recordedInvocation)

        XCTAssertEqual(invocation.executable, "/usr/bin/chromium")
        XCTAssertEqual(invocation.environment, ["PATH": "/usr/bin"])
        XCTAssertEqual(invocation.timeout, 4)
        XCTAssertTrue(invocation.arguments.contains("--headless=new"))
        XCTAssertTrue(invocation.arguments.contains("--dump-dom"))
        XCTAssertTrue(invocation.arguments.contains("--virtual-time-budget=1500"))
        XCTAssertTrue(invocation.arguments.contains("--no-sandbox"))
        XCTAssertTrue(invocation.arguments.contains { $0.hasPrefix("--user-data-dir=") })
        XCTAssertEqual(invocation.arguments.last, "https://example.test/app")

        XCTAssertEqual(snapshot.finalURL.absoluteString, "https://example.test/app")
        XCTAssertEqual(snapshot.title, "Rendered app")
        XCTAssertEqual(snapshot.outline, [
            "H1: Dashboard",
            "Button: Launch",
            "Input: Search everything"
        ])
        XCTAssertEqual(snapshot.visibleText, "Dashboard Launch Dynamic total: 42")
        XCTAssertEqual(snapshot.viewportDescription, "Headless Chromium browser process")
        XCTAssertTrue(snapshot.html?.contains("Dynamic total: 42") == true)
    }

    func testCapturerReportsNoRenderedSessionWhenBrowserIsMissing() async {
        let capturer = ChromiumBrowserLiveDOMCapturer(
            executableLocator: StaticBrowserExecutableLocator(executable: nil),
            processRunner: RecordingBrowserProcessRunner(result: .success(BrowserProcessRenderResult(
                stdout: "",
                stderr: "",
                exitCode: 0
            )))
        )

        do {
            _ = try await capturer.captureLiveDOM(for: URL(string: "https://example.test")!)
            XCTFail("Expected missing browser executable to fail.")
        } catch let failure as BrowserLiveDOMCaptureFailure {
            XCTAssertEqual(failure, .noRenderedSession)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCapturerSurfacesBrowserProcessFailure() async {
        let capturer = ChromiumBrowserLiveDOMCapturer(
            executableLocator: StaticBrowserExecutableLocator(executable: "/usr/bin/chromium"),
            processRunner: RecordingBrowserProcessRunner(result: .success(BrowserProcessRenderResult(
                stdout: "",
                stderr: "render failed",
                exitCode: 2
            )))
        )

        do {
            _ = try await capturer.captureLiveDOM(for: URL(string: "https://example.test")!)
            XCTFail("Expected non-zero browser exit to fail.")
        } catch let failure as BrowserLiveDOMCaptureFailure {
            guard case .transport(let message) = failure else {
                return XCTFail("Expected transport failure, got \(failure)")
            }
            XCTAssertTrue(message.contains("code 2"), message)
            XCTAssertTrue(message.contains("render failed"), message)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCapturerRejectsUnsupportedSchemesBeforeLaunching() async {
        let runner = RecordingBrowserProcessRunner(result: .success(BrowserProcessRenderResult(
            stdout: "<html></html>",
            stderr: "",
            exitCode: 0
        )))
        let capturer = ChromiumBrowserLiveDOMCapturer(
            executableLocator: StaticBrowserExecutableLocator(executable: "/usr/bin/chromium"),
            processRunner: runner
        )

        do {
            _ = try await capturer.captureLiveDOM(for: URL(string: "ftp://example.test/file")!)
            XCTFail("Expected unsupported scheme to fail.")
        } catch let failure as BrowserLiveDOMCaptureFailure {
            guard case .transport(let message) = failure else {
                return XCTFail("Expected transport failure, got \(failure)")
            }
            XCTAssertTrue(message.contains("http, https, and file"), message)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let invocations = await runner.allInvocations()
        XCTAssertTrue(invocations.isEmpty)
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillCodeChromiumBrowserTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

private struct StaticBrowserExecutableLocator: BrowserProcessExecutableLocating {
    var executable: String?

    func browserExecutable() -> String? {
        executable
    }
}

private actor RecordingBrowserProcessRunner: BrowserProcessRunning {
    enum ResultMode {
        case success(BrowserProcessRenderResult)
        case failure(any Error)
    }

    private let result: ResultMode
    private var invocations: [BrowserProcessInvocation] = []

    init(result: ResultMode) {
        self.result = result
    }

    func run(_ invocation: BrowserProcessInvocation) async throws -> BrowserProcessRenderResult {
        invocations.append(invocation)
        switch result {
        case .success(let output):
            return output
        case .failure(let error):
            throw error
        }
    }

    func firstInvocation() -> BrowserProcessInvocation? {
        invocations.first
    }

    func allInvocations() -> [BrowserProcessInvocation] {
        invocations
    }
}
