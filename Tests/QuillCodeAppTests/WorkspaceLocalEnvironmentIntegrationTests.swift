import XCTest
import QuillCodeCore
@testable import QuillCodeApp

@MainActor
final class WorkspaceLocalEnvironmentIntegrationTests: XCTestCase {
    func testLocalEnvironmentActionsLoadAndRunFromCommandPaletteIDs() throws {
        let setup = try makeLocalEnvironmentProject(name: "Local Env Project") { actionsDirectory in
            try "printf local-env-ok".write(
                to: actionsDirectory.appendingPathComponent("bootstrap-env.sh"),
                atomically: true,
                encoding: .utf8
            )
        }

        let action = try XCTUnwrap(setup.model.selectedProject?.localActions.first)
        XCTAssertEqual(action.title, "Bootstrap Env")
        XCTAssertEqual(action.relativePath, ".quillcode/actions/bootstrap-env.sh")
        XCTAssertTrue(setup.model.runWorkspaceCommand(action.id, workspaceRoot: setup.root))

        let card = try XCTUnwrap(setup.model.currentToolCards.last)
        XCTAssertEqual(card.title, "host.shell.run")
        XCTAssertEqual(card.status, .done)
        XCTAssertEqual(try shellResult(from: card).stdout, "local-env-ok")
    }

    func testLocalEnvironmentActionMetadataInjectsBoundedEnvironment() throws {
        let setup = try makeLocalEnvironmentProject(name: "Local Env Metadata Project") { actionsDirectory in
            try #"printf "%s|%s|%s|%s" "$QUILL_ENV" "$CACHE_DIR" "$QUOTED_VALUE" "$(printenv BAD-KEY || true)""#.write(
                to: actionsDirectory.appendingPathComponent("env-check.sh"),
                atomically: true,
                encoding: .utf8
            )
            try """
            {
              "title": "Environment Check",
              "environment": {
                "QUILL_ENV": "dev",
                "CACHE_DIR": ".cache/quill",
                "QUOTED_VALUE": "it's ok",
                "BAD-KEY": "ignored",
                "MULTILINE": "bad\\nvalue"
              }
            }
            """.write(
                to: actionsDirectory.appendingPathComponent("env-check.json"),
                atomically: true,
                encoding: .utf8
            )
        }

        let action = try XCTUnwrap(setup.model.selectedProject?.localActions.first)
        XCTAssertEqual(action.title, "Environment Check")
        XCTAssertEqual(action.environment, [
            "CACHE_DIR": ".cache/quill",
            "QUILL_ENV": "dev",
            "QUOTED_VALUE": "it's ok"
        ])
        XCTAssertEqual(action.command, #"sh '.quillcode/actions/env-check.sh'"#)
        XCTAssertTrue(setup.model.runWorkspaceCommand(action.id, workspaceRoot: setup.root))

        let card = try XCTUnwrap(setup.model.currentToolCards.last)
        XCTAssertTrue(card.inputJSON?.contains(#""environment""#) == true)
        XCTAssertTrue(card.inputJSON?.contains("QUILL_ENV") == true)
        XCTAssertTrue(card.inputJSON?.contains(ToolCall.redactedEnvironmentValue) == true)
        XCTAssertFalse(card.inputJSON?.contains(".cache/quill") == true)
        XCTAssertFalse(card.inputJSON?.contains("it's ok") == true)
        XCTAssertEqual(try shellResult(from: card).stdout, "dev|.cache/quill|it's ok|")
    }

    func testLocalEnvironmentActionMetadataRunsFromBoundedWorkingDirectory() throws {
        let setup = try makeLocalEnvironmentProject(name: "Local Env CWD Project") { root, actionsDirectory in
            let appDirectory = root.appendingPathComponent("app")
            try FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
            try "marker-ok".write(
                to: appDirectory.appendingPathComponent("marker.txt"),
                atomically: true,
                encoding: .utf8
            )
            try #"printf "%s|%s" "$(basename "$PWD")" "$(cat marker.txt)""#.write(
                to: actionsDirectory.appendingPathComponent("cwd-check.sh"),
                atomically: true,
                encoding: .utf8
            )
            try """
            {
              "title": "CWD Check",
              "workingDirectory": "app"
            }
            """.write(
                to: actionsDirectory.appendingPathComponent("cwd-check.json"),
                atomically: true,
                encoding: .utf8
            )
        }

        let action = try XCTUnwrap(setup.model.selectedProject?.localActions.first)
        XCTAssertEqual(action.workingDirectory, "app")
        XCTAssertEqual(action.command, #"cd 'app' && sh '../.quillcode/actions/cwd-check.sh'"#)
        XCTAssertTrue(setup.model.runWorkspaceCommand(action.id, workspaceRoot: setup.root))
        XCTAssertEqual(try shellResult(from: setup.model.currentToolCards.last).stdout, "app|marker-ok")
    }

    func testLocalEnvironmentActionMetadataPassesBoundedTimeout() throws {
        let setup = try makeLocalEnvironmentProject(name: "Local Env Timeout Project") { actionsDirectory in
            try "sleep 2; printf should-not-print".write(
                to: actionsDirectory.appendingPathComponent("slow.sh"),
                atomically: true,
                encoding: .utf8
            )
            try """
            {
              "title": "Slow Check",
              "timeoutSeconds": 1
            }
            """.write(
                to: actionsDirectory.appendingPathComponent("slow.json"),
                atomically: true,
                encoding: .utf8
            )
        }

        let action = try XCTUnwrap(setup.model.selectedProject?.localActions.first)
        XCTAssertEqual(action.timeoutSeconds, 1)
        XCTAssertTrue(setup.model.runWorkspaceCommand(action.id, workspaceRoot: setup.root))

        let card = try XCTUnwrap(setup.model.currentToolCards.last)
        XCTAssertEqual(card.status, .failed)
        let result = try shellResult(from: card)
        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.error, "Command timed out after 1s.")
    }

    private func makeLocalEnvironmentProject(
        name: String,
        configureActions: (URL) throws -> Void
    ) throws -> (root: URL, actionsDirectory: URL, model: QuillCodeWorkspaceModel) {
        try makeLocalEnvironmentProject(name: name) { _, actionsDirectory in
            try configureActions(actionsDirectory)
        }
    }

    private func makeLocalEnvironmentProject(
        name: String,
        configureActions: (URL, URL) throws -> Void
    ) throws -> (root: URL, actionsDirectory: URL, model: QuillCodeWorkspaceModel) {
        let root = try makeQuillCodeTestDirectory()
        let actionsDirectory = root.appendingPathComponent(".quillcode/actions")
        try FileManager.default.createDirectory(at: actionsDirectory, withIntermediateDirectories: true)
        try configureActions(root, actionsDirectory)

        let model = QuillCodeWorkspaceModel()
        let projectID = model.addProject(path: root, name: name)
        model.selectProject(projectID)
        return (root, actionsDirectory, model)
    }

    private func shellResult(from card: ToolCardState?) throws -> ToolResult {
        let card = try XCTUnwrap(card)
        let outputJSON = try XCTUnwrap(card.outputJSON)
        return try JSONHelpers.decode(ToolResult.self, from: outputJSON)
    }
}
