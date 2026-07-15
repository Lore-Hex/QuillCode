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

    private func runRequest(_ command: CLICommand) throws -> CLIRunRequest {
        guard case .run(let request) = command else {
            throw XCTSkip("Expected run command")
        }
        return request
    }
}
