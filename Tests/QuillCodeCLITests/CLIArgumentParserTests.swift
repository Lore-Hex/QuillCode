import Foundation
@testable import QuillCodeCLI
import QuillCodeCore
import XCTest

final class CLIArgumentParserTests: XCTestCase {
    private let parser = CLIArgumentParser()
    private let cwd = URL(fileURLWithPath: "/tmp/project")

    func testExecDefaultsToLiveReadOnlyRun() throws {
        let command = try parser.parse(["exec", "inspect", "the", "repo"], currentDirectory: cwd)
        let request = try runRequest(command)
        XCTAssertEqual(request.style, .exec)
        XCTAssertTrue(request.live)
        XCTAssertEqual(request.sandbox, .readOnly)
        XCTAssertEqual(request.prompt, "inspect the repo")
        XCTAssertEqual(request.cwd.path, cwd.path)
    }

    func testLegacyInvocationPreservesMockCompatibility() throws {
        let request = try runRequest(parser.parse(["run whoami"], currentDirectory: cwd))
        XCTAssertEqual(request.style, .legacy)
        XCTAssertFalse(request.live)
        XCTAssertNil(request.sandbox)
        XCTAssertEqual(request.prompt, "run whoami")
    }

    func testExecParsesAutomationOptionsAndEqualsSyntax() throws {
        let request = try runRequest(parser.parse([
            "--home", "/tmp/qc-home",
            "exec",
            "--mock",
            "--json",
            "--ephemeral",
            "--sandbox=workspace-write",
            "--mode", "review",
            "--model=trustedrouter/fast",
            "-C", "/tmp/repo",
            "-o", "/tmp/final.txt",
            "--output-schema", "/tmp/schema.json",
            "--image", "/tmp/a.png",
            "--ignore-user-config",
            "--ignore-rules",
            "--skip-git-repo-check",
            "do", "the", "work"
        ], currentDirectory: cwd))
        XCTAssertFalse(request.live)
        XCTAssertTrue(request.emitsJSONLines)
        XCTAssertTrue(request.ephemeral)
        XCTAssertEqual(request.sandbox, .workspaceWrite)
        XCTAssertEqual(request.explicitMode, .review)
        XCTAssertEqual(request.model, "trustedrouter/fast")
        XCTAssertEqual(request.cwd.path, "/tmp/repo")
        XCTAssertEqual(request.home?.path, "/tmp/qc-home")
        XCTAssertEqual(request.outputLastMessageURL?.path, "/tmp/final.txt")
        XCTAssertEqual(request.outputSchemaURL?.path, "/tmp/schema.json")
        XCTAssertEqual(request.imageURLs.map(\.path), ["/tmp/a.png"])
        XCTAssertTrue(request.ignoresUserConfig)
        XCTAssertTrue(request.ignoresPermissionRules)
        XCTAssertTrue(request.skipsGitRepositoryCheck)
        XCTAssertEqual(request.prompt, "do the work")
    }

    func testResumeParsesLastAndExactThread() throws {
        let last = try runRequest(parser.parse([
            "exec", "resume", "--last", "continue"
        ], currentDirectory: cwd))
        XCTAssertEqual(last.resumeTarget, .last)

        let id = UUID()
        let exact = try runRequest(parser.parse([
            "exec", "resume", id.uuidString, "continue"
        ], currentDirectory: cwd))
        XCTAssertEqual(exact.resumeTarget, .id(id))
    }

    func testLoneDashIsAStdinPrompt() throws {
        let request = try runRequest(parser.parse(["exec", "-"], currentDirectory: cwd))
        XCTAssertEqual(request.prompt, "-")
    }

    func testRelativePathsResolveAgainstSuppliedCurrentDirectory() throws {
        let request = try runRequest(parser.parse([
            "--home", ".quill-home",
            "exec", "-C", "nested", "--image", "fixture.png",
            "-o", "answer.txt", "--output-schema", "schema.json", "inspect"
        ], currentDirectory: cwd))
        XCTAssertEqual(request.home?.path, "/tmp/project/.quill-home")
        XCTAssertEqual(request.cwd.path, "/tmp/project/nested")
        XCTAssertEqual(request.imageURLs.first?.path, "/tmp/project/fixture.png")
        XCTAssertEqual(request.outputLastMessageURL?.path, "/tmp/project/answer.txt")
        XCTAssertEqual(request.outputSchemaURL?.path, "/tmp/project/schema.json")
    }

    func testParserRejectsUnknownAndMissingOptions() {
        XCTAssertThrowsError(try parser.parse(["exec", "--wat", "prompt"], currentDirectory: cwd))
        XCTAssertThrowsError(try parser.parse(["exec", "--model"], currentDirectory: cwd))
        XCTAssertThrowsError(try parser.parse(["exec", "resume", "not-a-uuid", "prompt"], currentDirectory: cwd))
        XCTAssertThrowsError(try parser.parse(["exec", "one", "-", "two"], currentDirectory: cwd))
    }

    func testAppServerDefaultsToLiveStdioAndParsesOverrides() throws {
        let defaults = try appServerRequest(parser.parse(["app-server"], currentDirectory: cwd))
        XCTAssertEqual(defaults.transport, .stdio)
        XCTAssertTrue(defaults.live)

        let configured = try appServerRequest(parser.parse([
            "--home", ".quill-home",
            "app-server",
            "--listen=stdio://",
            "--mock",
            "--api-key", "test-key",
            "--model", "trustedrouter/deepseek-v4-flash",
            "--base-url", "https://example.test/v1"
        ], currentDirectory: cwd))
        XCTAssertEqual(configured.home?.path, "/tmp/project/.quill-home")
        XCTAssertEqual(configured.transport, .stdio)
        XCTAssertFalse(configured.live)
        XCTAssertEqual(configured.apiKey, "test-key")
        XCTAssertEqual(configured.model, "trustedrouter/deepseek-v4-flash")
        XCTAssertEqual(configured.baseURL, "https://example.test/v1")
    }

    func testAppServerParsesFeatureOverridesAndRejectsUnknownFlags() throws {
        let configured = try appServerRequest(parser.parse([
            "app-server",
            "--disable", "memories",
            "--enable=memories",
            "--disable", "hooks"
        ], currentDirectory: cwd))
        XCTAssertEqual(configured.featureEnablement, [
            "hooks": false,
            "memories": true
        ])

        XCTAssertThrowsError(try parser.parse([
            "app-server", "--enable", "not-a-feature"
        ], currentDirectory: cwd)) { error in
            XCTAssertEqual(error as? CLIError, .unknownFeatureFlag("not-a-feature"))
        }
    }

    func testAppServerRejectsUnsupportedTransportAndUnknownOptions() {
        for transport in [
            "ws://localhost:4500",
            "ws://127.0.0.1",
            "ws://127.0.0.1:4500/path",
            "unix://relative.sock",
            "unix:///tmp/socket?query",
            "unix:///tmp/socket#fragment"
        ] {
            XCTAssertThrowsError(try parser.parse([
                "app-server", "--listen", transport
            ], currentDirectory: cwd))
        }
        XCTAssertThrowsError(try parser.parse([
            "app-server", "--unknown"
        ], currentDirectory: cwd))
    }

    func testAppServerParsesWebSocketAndOffTransports() throws {
        let ipv4 = try appServerRequest(parser.parse([
            "app-server", "--listen", "ws://127.0.0.1:4500", "--mock"
        ], currentDirectory: cwd))
        XCTAssertEqual(ipv4.transport, .webSocket(host: "127.0.0.1", port: 4_500))
        XCTAssertEqual(ipv4.transport.rawValue, "ws://127.0.0.1:4500")

        let ipv6 = try appServerRequest(parser.parse([
            "app-server", "--listen=ws://[::1]:0"
        ], currentDirectory: cwd))
        XCTAssertEqual(ipv6.transport, .webSocket(host: "::1", port: 0))
        XCTAssertEqual(ipv6.transport.rawValue, "ws://[::1]:0")

        let off = try appServerRequest(parser.parse([
            "app-server", "--listen", "off"
        ], currentDirectory: cwd))
        XCTAssertEqual(off.transport, .off)
    }

    func testAppServerParsesAndValidatesWebSocketAuth() throws {
        let capability = try appServerRequest(parser.parse([
            "app-server",
            "--listen", "ws://0.0.0.0:4500",
            "--ws-auth", "capability-token",
            "--ws-token-file", "/tmp/quillcode-token"
        ], currentDirectory: cwd))
        XCTAssertEqual(capability.webSocketAuth.mode, .capabilityToken)
        XCTAssertEqual(capability.webSocketAuth.tokenFile, "/tmp/quillcode-token")

        let signed = try appServerRequest(parser.parse([
            "app-server",
            "--listen=ws://[::]:4500",
            "--ws-auth=signed-bearer-token",
            "--ws-shared-secret-file=/tmp/quillcode-secret",
            "--ws-issuer", "issuer",
            "--ws-audience", "client",
            "--ws-max-clock-skew-seconds", "12"
        ], currentDirectory: cwd))
        XCTAssertEqual(signed.webSocketAuth.mode, .signedBearerToken)
        XCTAssertEqual(signed.webSocketAuth.sharedSecretFile, "/tmp/quillcode-secret")
        XCTAssertEqual(signed.webSocketAuth.issuer, "issuer")
        XCTAssertEqual(signed.webSocketAuth.audience, "client")
        XCTAssertEqual(signed.webSocketAuth.maxClockSkewSeconds, 12)
    }

    func testAppServerRejectsInvalidWebSocketAuthCombinations() {
        let invalidArguments = [
            ["app-server", "--ws-auth", "capability-token", "--ws-token-file", "/tmp/token"],
            ["app-server", "--listen", "ws://127.0.0.1:1", "--ws-token-file", "/tmp/token"],
            ["app-server", "--listen", "ws://127.0.0.1:1", "--ws-auth", "capability-token"],
            [
                "app-server", "--listen", "ws://127.0.0.1:1",
                "--ws-auth", "capability-token",
                "--ws-token-file", "/tmp/token",
                "--ws-token-sha256", String(repeating: "a", count: 64)
            ],
            [
                "app-server", "--listen", "ws://127.0.0.1:1",
                "--ws-auth", "signed-bearer-token"
            ],
            [
                "app-server", "--listen", "ws://127.0.0.1:1",
                "--ws-auth", "capability-token",
                "--ws-token-sha256", "bad"
            ]
        ]
        for arguments in invalidArguments {
            XCTAssertThrowsError(try parser.parse(arguments, currentDirectory: cwd), "\(arguments)")
        }
    }

    func testAppServerParsesDefaultAndExplicitUnixSockets() throws {
        let defaultSocket = try appServerRequest(parser.parse([
            "app-server", "--listen", "unix://", "--mock"
        ], currentDirectory: cwd))
        XCTAssertEqual(defaultSocket.transport, .unix(path: nil))

        let explicitSocket = try appServerRequest(parser.parse([
            "app-server", "--listen=unix:///tmp/quill code.sock"
        ], currentDirectory: cwd))
        XCTAssertEqual(explicitSocket.transport, .unix(path: "/tmp/quill code.sock"))
        XCTAssertEqual(explicitSocket.transport.rawValue, "unix:///tmp/quill code.sock")
    }

    func testMCPServerDefaultsToLiveAndParsesRuntimeOverrides() throws {
        let defaults = try mcpServerRequest(parser.parse(["mcp-server"], currentDirectory: cwd))
        XCTAssertTrue(defaults.live)

        let configured = try mcpServerRequest(parser.parse([
            "--home", ".quill-home",
            "mcp-server",
            "--mock",
            "--api-key", "test-key",
            "--model=trustedrouter/deepseek-v4-flash",
            "--base-url", "https://example.test/v1"
        ], currentDirectory: cwd))
        XCTAssertEqual(configured.home?.path, "/tmp/project/.quill-home")
        XCTAssertFalse(configured.live)
        XCTAssertEqual(configured.apiKey, "test-key")
        XCTAssertEqual(configured.model, "trustedrouter/deepseek-v4-flash")
        XCTAssertEqual(configured.baseURL, "https://example.test/v1")
        XCTAssertThrowsError(try parser.parse(["mcp-server", "--listen", "stdio://"], currentDirectory: cwd))
    }

    func testDoctorParsesGlobalHomeAndOutputOptions() throws {
        let request = try doctorRequest(parser.parse([
            "--home", ".quill-home",
            "doctor", "--json", "--summary", "--all", "--no-color", "--ascii"
        ], currentDirectory: cwd))

        XCTAssertEqual(request.home?.path, "/tmp/project/.quill-home")
        XCTAssertTrue(request.emitsJSON)
        XCTAssertTrue(request.summaryOnly)
        XCTAssertTrue(request.expandsLongLists)
        XCTAssertTrue(request.disablesColor)
        XCTAssertTrue(request.usesASCII)
        XCTAssertFalse(request.showsHelp)
    }

    func testDoctorHelpAndInvalidOptions() throws {
        let help = try doctorRequest(parser.parse(["doctor", "-h"], currentDirectory: cwd))
        XCTAssertTrue(help.showsHelp)

        XCTAssertThrowsError(try parser.parse(["doctor", "--unknown"], currentDirectory: cwd))
        XCTAssertThrowsError(try parser.parse(["doctor", "unexpected"], currentDirectory: cwd))
    }

    func testReviewParsesEveryTargetShape() throws {
        XCTAssertEqual(
            try reviewRequest(parser.parse(["review", "--uncommitted"], currentDirectory: cwd)).target,
            .uncommitted
        )
        XCTAssertEqual(
            try reviewRequest(parser.parse(["review", "--base", "origin/main"], currentDirectory: cwd)).target,
            .baseBranch("origin/main")
        )
        let commit = try reviewRequest(parser.parse([
            "review", "--commit=HEAD", "--title", "Fix cancellation"
        ], currentDirectory: cwd))
        XCTAssertEqual(commit.target, .commit("HEAD"))
        XCTAssertEqual(commit.title, "Fix cancellation")
        XCTAssertEqual(
            try reviewRequest(parser.parse([
                "review", "Focus", "on", "the", "streaming", "path"
            ], currentDirectory: cwd)).target,
            .custom("Focus on the streaming path")
        )
        XCTAssertEqual(
            try reviewRequest(parser.parse(["review", "-"], currentDirectory: cwd)).target,
            .custom("-")
        )
    }

    func testReviewParsesRuntimeOptionsAndRelativeWorkingDirectory() throws {
        let request = try reviewRequest(parser.parse([
            "--home", ".quill-home",
            "review", "--uncommitted", "--mock",
            "--api-key", "test-key",
            "--model=trustedrouter/deepseek-v4-flash",
            "--base-url", "https://example.test/v1",
            "-C", "nested",
            "--ignore-user-config"
        ], currentDirectory: cwd))

        XCTAssertFalse(request.live)
        XCTAssertEqual(request.apiKey, "test-key")
        XCTAssertEqual(request.model, "trustedrouter/deepseek-v4-flash")
        XCTAssertEqual(request.baseURL, "https://example.test/v1")
        XCTAssertEqual(request.cwd.path, "/tmp/project/nested")
        XCTAssertEqual(request.home?.path, "/tmp/project/.quill-home")
        XCTAssertTrue(request.ignoresUserConfig)
    }

    func testReviewHelpDoesNotRequireTarget() throws {
        let request = try reviewRequest(parser.parse(["review", "--help"], currentDirectory: cwd))
        XCTAssertTrue(request.showsHelp)
        XCTAssertNil(request.target)
    }

    func testReviewRejectsMissingConflictingAndInvalidTargets() {
        assertCLIError(.missingReviewTarget, parsing: ["review"])
        assertCLIError(
            .conflictingReviewTargets,
            parsing: ["review", "--uncommitted", "custom focus"]
        )
        assertCLIError(
            .conflictingReviewTargets,
            parsing: ["review", "--base", "main", "--commit", "HEAD"]
        )
        assertCLIError(
            .reviewTitleRequiresCommit,
            parsing: ["review", "--uncommitted", "--title", "Not a commit"]
        )
        assertCLIError(
            .invalidOptionValue(option: "review prompt", value: "- extra"),
            parsing: ["review", "-", "extra"]
        )
        XCTAssertThrowsError(try parser.parse([
            "review", "--commit", "HEAD\nother"
        ], currentDirectory: cwd))
        XCTAssertThrowsError(try parser.parse([
            "review", "--unknown", "value"
        ], currentDirectory: cwd))
    }

    private func runRequest(_ command: CLICommand) throws -> CLIRunRequest {
        guard case .run(let request) = command else {
            throw XCTSkip("Expected run command")
        }
        return request
    }

    private func appServerRequest(_ command: CLICommand) throws -> CLIAppServerRequest {
        guard case .appServer(let request) = command else {
            throw XCTSkip("Expected app-server command")
        }
        return request
    }

    private func mcpServerRequest(_ command: CLICommand) throws -> CLIMCPServerRequest {
        guard case .mcpServer(let request) = command else {
            throw XCTSkip("Expected mcp-server command")
        }
        return request
    }

    private func doctorRequest(_ command: CLICommand) throws -> CLIDoctorRequest {
        guard case .doctor(let request) = command else {
            throw XCTSkip("Expected doctor command")
        }
        return request
    }

    private func reviewRequest(_ command: CLICommand) throws -> CLIReviewRequest {
        guard case .review(let request) = command else {
            throw XCTSkip("Expected review command")
        }
        return request
    }

    private func assertCLIError(
        _ expected: CLIError,
        parsing arguments: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try parser.parse(arguments, currentDirectory: cwd),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? CLIError, expected, file: file, line: line)
        }
    }
}
