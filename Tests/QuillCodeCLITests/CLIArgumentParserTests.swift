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

    func testAppServerRejectsUnsupportedTransportAndUnknownOptions() {
        XCTAssertThrowsError(try parser.parse([
            "app-server", "--listen", "ws://127.0.0.1:4500"
        ], currentDirectory: cwd))
        XCTAssertThrowsError(try parser.parse([
            "app-server", "--unknown"
        ], currentDirectory: cwd))
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
