import XCTest
import QuillCodeTools
@testable import QuillCodeApp

final class WorktreeSetupScriptLoaderTests: XCTestCase {
    func testPlatformScriptOverridesDefaultAndUsesMetadata() throws {
        let root = try makeQuillCodeTestDirectory()
        let directory = root.appendingPathComponent(".quillcode")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "printf default".write(
            to: directory.appendingPathComponent("setup.sh"),
            atomically: true,
            encoding: .utf8
        )
        try "printf macos".write(
            to: directory.appendingPathComponent("setup.macos.sh"),
            atomically: true,
            encoding: .utf8
        )
        try """
        {
          "environment": {"QUILL_SETUP": "ready", "BAD-KEY": "ignored"},
          "timeoutSeconds": 45
        }
        """.write(
            to: directory.appendingPathComponent("setup.macos.json"),
            atomically: true,
            encoding: .utf8
        )

        let script = try XCTUnwrap(WorktreeSetupScriptLoader.load(
            from: root,
            configuration: WorktreeSetupConfiguration(),
            operatingSystem: .macOS
        ))

        XCTAssertEqual(script.relativePath, ".quillcode/setup.macos.sh")
        XCTAssertEqual(script.command, "sh '.quillcode/setup.macos.sh'")
        XCTAssertEqual(script.environment, ["QUILL_SETUP": "ready"])
        XCTAssertEqual(script.timeoutSeconds, 45)
    }

    func testMissingPlatformScriptFallsBackToDefault() throws {
        let root = try makeQuillCodeTestDirectory()
        let directory = root.appendingPathComponent(".quillcode")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "printf default".write(
            to: directory.appendingPathComponent("setup.sh"),
            atomically: true,
            encoding: .utf8
        )

        let script = try XCTUnwrap(WorktreeSetupScriptLoader.load(
            from: root,
            configuration: WorktreeSetupConfiguration(),
            operatingSystem: .linux
        ))

        XCTAssertEqual(script.relativePath, ".quillcode/setup.sh")
        XCTAssertEqual(script.timeoutSeconds, WorktreeSetupScriptLoader.defaultTimeoutSeconds)
    }

    func testConfiguredScriptPathIsResolvedInsideWorktree() throws {
        let root = try makeQuillCodeTestDirectory()
        let directory = root.appendingPathComponent("tools/bootstrap")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "printf custom".write(
            to: directory.appendingPathComponent("prepare.sh"),
            atomically: true,
            encoding: .utf8
        )

        let script = try XCTUnwrap(WorktreeSetupScriptLoader.load(
            from: root,
            configuration: WorktreeSetupConfiguration(
                scriptPath: "tools/bootstrap/prepare.sh",
                macOSScriptPath: "tools/bootstrap/missing-macos.sh",
                linuxScriptPath: "tools/bootstrap/missing-linux.sh"
            ),
            operatingSystem: .other
        ))

        XCTAssertEqual(script.command, "sh 'tools/bootstrap/prepare.sh'")
    }

    func testSymlinkOutsideWorktreeIsRejected() throws {
        let root = try makeQuillCodeTestDirectory()
        let outside = try makeQuillCodeTestDirectory()
        let directory = root.appendingPathComponent(".quillcode")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let outsideScript = outside.appendingPathComponent("setup.sh")
        try "printf escaped".write(to: outsideScript, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent("setup.sh"),
            withDestinationURL: outsideScript
        )

        XCTAssertNil(WorktreeSetupScriptLoader.load(
            from: root,
            configuration: WorktreeSetupConfiguration(),
            operatingSystem: .other
        ))
    }

    func testInvalidExplicitConfigurationNeverFallsBackToDefaultScript() throws {
        let root = try makeQuillCodeTestDirectory()
        let directory = root.appendingPathComponent(".quillcode")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "printf should-not-run".write(
            to: directory.appendingPathComponent("setup.sh"),
            atomically: true,
            encoding: .utf8
        )
        let configuration = WorktreeSetupConfiguration(
            scriptPath: "../escape.sh",
            isExplicitlyConfigured: true
        )

        XCTAssertFalse(configuration.isValid)
        XCTAssertNil(WorktreeSetupScriptLoader.load(
            from: root,
            configuration: configuration,
            operatingSystem: .other
        ))
    }

    func testNamedEnvironmentResolvesItsPlatformScript() throws {
        let root = try makeQuillCodeTestDirectory()
        let directory = root.appendingPathComponent(".quillcode/environments/development")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "printf development".write(
            to: directory.appendingPathComponent("setup.macos.sh"),
            atomically: true,
            encoding: .utf8
        )
        let environment = try XCTUnwrap(WorktreeLocalEnvironment(id: "development", title: "Development"))
        let configuration = WorkspaceProjectConfiguration(
            localEnvironments: [environment],
            defaultLocalEnvironmentID: "development"
        )

        let resolution = WorktreeSetupScriptLoader.resolve(
            from: root,
            configuration: configuration,
            selection: .automatic,
            operatingSystem: .macOS
        )

        guard case .script(let script) = resolution else {
            return XCTFail("Expected named setup script, got \(resolution)")
        }
        XCTAssertEqual(script.relativePath, ".quillcode/environments/development/setup.macos.sh")
        XCTAssertEqual(script.environmentID, "development")
    }

    func testExplicitNoSetupSkipsAvailableScripts() throws {
        let root = try makeQuillCodeTestDirectory()
        let directory = root.appendingPathComponent(".quillcode")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "printf default".write(
            to: directory.appendingPathComponent("setup.sh"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertEqual(
            WorktreeSetupScriptLoader.resolve(
                from: root,
                configuration: WorkspaceProjectConfiguration(),
                selection: .none
            ),
            .skipped
        )
    }

    func testMissingNamedEnvironmentReturnsActionableFailure() throws {
        let resolution = WorktreeSetupScriptLoader.resolve(
            from: try makeQuillCodeTestDirectory(),
            configuration: WorkspaceProjectConfiguration(),
            selection: .named("missing")
        )

        XCTAssertEqual(
            resolution,
            .failure("The selected local environment 'missing' is not configured in this checkout.")
        )
    }

    func testInvalidNamedEnvironmentReturnsActionableFailure() throws {
        let environment = try XCTUnwrap(WorktreeLocalEnvironment(
            id: "broken",
            scriptPath: "../escape.sh"
        ))
        let resolution = WorktreeSetupScriptLoader.resolve(
            from: try makeQuillCodeTestDirectory(),
            configuration: WorkspaceProjectConfiguration(localEnvironments: [environment]),
            selection: .named("broken")
        )

        XCTAssertEqual(
            resolution,
            .failure(
                "The local environment 'Broken' has invalid setup paths. "
                    + "Paths must be relative .sh files inside the project."
            )
        )
    }
}
