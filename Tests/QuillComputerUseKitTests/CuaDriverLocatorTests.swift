import XCTest
@testable import QuillComputerUseKit

final class CuaDriverLocatorTests: XCTestCase {
    // MARK: - Path resolution

    func testExplicitPathWins() {
        let resolved = CuaDriverLocator.resolveDriverPath(
            explicitPath: "/custom/cua-driver",
            environment: ["QUILLCODE_CUA_DRIVER_PATH": "/env/cua-driver"],
            candidatePaths: ["/opt/homebrew/bin/cua-driver"],
            fileExists: { _ in true }
        )
        XCTAssertEqual(resolved, "/custom/cua-driver")
    }

    func testEnvironmentPathBeatsCandidates() {
        let resolved = CuaDriverLocator.resolveDriverPath(
            explicitPath: nil,
            environment: ["QUILLCODE_CUA_DRIVER_PATH": "/env/cua-driver"],
            candidatePaths: ["/opt/homebrew/bin/cua-driver"],
            fileExists: { _ in true }
        )
        XCTAssertEqual(resolved, "/env/cua-driver")
    }

    func testFallsThroughToFirstExistingCandidate() {
        let resolved = CuaDriverLocator.resolveDriverPath(
            explicitPath: nil,
            environment: [:],
            candidatePaths: ["/missing/cua-driver", "/opt/homebrew/bin/cua-driver"],
            fileExists: { $0 == "/opt/homebrew/bin/cua-driver" }
        )
        XCTAssertEqual(resolved, "/opt/homebrew/bin/cua-driver")
    }

    func testReturnsNilWhenNothingExists() {
        let resolved = CuaDriverLocator.resolveDriverPath(
            explicitPath: "/custom/cua-driver",
            environment: ["QUILLCODE_CUA_DRIVER_PATH": "/env/cua-driver"],
            candidatePaths: ["/opt/homebrew/bin/cua-driver"],
            fileExists: { _ in false }
        )
        XCTAssertNil(resolved)
    }

    func testTildeExpansionForExplicitPath() {
        var resolvedInput: String?
        _ = CuaDriverLocator.resolveDriverPath(
            explicitPath: "~/bin/cua-driver",
            environment: [:],
            candidatePaths: [],
            fileExists: { path in resolvedInput = path; return true }
        )
        XCTAssertNotNil(resolvedInput)
        XCTAssertFalse(resolvedInput?.hasPrefix("~") ?? true, "tilde should be expanded before existence check")
    }

    func testCandidatePathsIncludeQuillcodeToolsAndHomebrew() {
        let candidates = CuaDriverLocator.candidatePaths(home: "/Users/me")
        XCTAssertEqual(candidates.first, "/Users/me/.quillcode/tools/cua-driver")
        XCTAssertTrue(candidates.contains("/opt/homebrew/bin/cua-driver"))
        XCTAssertTrue(candidates.contains("/usr/local/bin/cua-driver"))
    }

    // MARK: - Status parsing

    func testStatusFromCheckPermissionsBothGranted() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "accessibility": true, "screen_recording": true, "screen_recording_capturable": true,
        ])
        let status = try XCTUnwrap(CuaDriverLocator.status(fromCheckPermissions: data))
        XCTAssertTrue(status.available)
        XCTAssertTrue(status.screenRecordingGranted)
        XCTAssertTrue(status.accessibilityGranted)
    }

    func testStatusFromCheckPermissionsPartialGrant() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "accessibility": false, "screen_recording": true,
        ])
        let status = try XCTUnwrap(CuaDriverLocator.status(fromCheckPermissions: data))
        XCTAssertFalse(status.available)
        XCTAssertTrue(status.screenRecordingGranted)
        XCTAssertFalse(status.accessibilityGranted)
        XCTAssertEqual(status.message, "Needs Accessibility")
    }

    func testStatusFromMalformedReturnsNil() {
        XCTAssertNil(CuaDriverLocator.status(fromCheckPermissions: Data("not json".utf8)))
        XCTAssertNil(CuaDriverLocator.status(fromCheckPermissions: Data("{}".utf8)))
    }

    // MARK: - makeBackendIfAvailable (scripted subprocess)

    func testMakeBackendReturnsNilWhenBinaryMissing() async {
        let locator = CuaDriverLocator(
            runProcess: { _, _ in .init(exitCode: 0, stdout: Data(), stderr: Data()) },
            fileExists: { _ in false }
        )
        let backend = await locator.makeBackendIfAvailable(environment: [:])
        XCTAssertNil(backend)
    }

    func testMakeBackendDisablesTelemetryAndProbesPermissions() async throws {
        let recorder = ProcessCallRecorder()
        let locator = CuaDriverLocator(
            runProcess: { arguments, _ in
                await recorder.record(arguments)
                // `telemetry disable` and any other non-call command → empty ok.
                if arguments.contains("call") {
                    let payload = try JSONSerialization.data(withJSONObject: [
                        "accessibility": true, "screen_recording": true,
                    ])
                    return .init(exitCode: 0, stdout: payload, stderr: Data())
                }
                return .init(exitCode: 0, stdout: Data(), stderr: Data())
            },
            fileExists: { $0 == "/opt/homebrew/bin/cua-driver" }
        )
        let backend = await locator.makeBackendIfAvailable(
            environment: ["HOME": "/Users/me"]
        )
        XCTAssertNotNil(backend)
        XCTAssertTrue(backend?.status.available ?? false)

        let commands = await recorder.commands
        XCTAssertTrue(commands.contains(["/opt/homebrew/bin/cua-driver", "telemetry", "disable"]))
        XCTAssertTrue(
            commands.contains { $0.contains("call") && $0.contains("check_permissions") },
            "must probe check_permissions"
        )
    }
}

private actor ProcessCallRecorder {
    private(set) var commands: [[String]] = []
    func record(_ arguments: [String]) { commands.append(arguments) }
}

final class CuaDriverProcessClientTests: XCTestCase {
    func testNonZeroExitThrowsToolFailedWithStderr() async {
        let client = CuaDriverProcessClient(
            driverPath: "/x/cua-driver",
            runProcess: { _, _ in
                .init(exitCode: 2, stdout: Data(), stderr: Data("boom".utf8))
            }
        )
        do {
            _ = try await client.callTool(name: "click", argumentsJSON: Data("{}".utf8))
            XCTFail("expected toolFailed")
        } catch let error as CuaDriverError {
            guard case let .toolFailed(tool, message) = error else { return XCTFail("wrong error: \(error)") }
            XCTAssertEqual(tool, "click")
            XCTAssertEqual(message, "boom")
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }

    func testZeroExitReturnsStdout() async throws {
        let client = CuaDriverProcessClient(
            driverPath: "/x/cua-driver",
            runProcess: { arguments, _ in
                XCTAssertEqual(arguments, ["/x/cua-driver", "call", "list_apps", "{}"])
                return .init(exitCode: 0, stdout: Data(#"{"apps":[]}"#.utf8), stderr: Data())
            }
        )
        let result = try await client.callTool(name: "list_apps", argumentsJSON: Data("{}".utf8))
        XCTAssertEqual(String(data: result, encoding: .utf8), #"{"apps":[]}"#)
    }
}
