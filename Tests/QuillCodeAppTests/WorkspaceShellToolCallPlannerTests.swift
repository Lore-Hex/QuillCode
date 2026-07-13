import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

final class WorkspaceShellToolCallPlannerTests: XCTestCase {
    func testLocalEnvironmentActionBuildsShellToolCallWithMetadata() throws {
        let action = LocalEnvironmentAction(
            id: "local-env:prepare",
            title: "Prepare",
            relativePath: ".quillcode/actions/prepare.sh",
            command: "sh '.quillcode/actions/prepare.sh'",
            environment: [
                "CACHE_DIR": ".cache/quill",
                "QUILL_ENV": "dev"
            ],
            timeoutSeconds: 120
        )

        let call = WorkspaceShellToolCallPlanner.localEnvironmentAction(action)
        let arguments = try ToolArguments(call.argumentsJSON)

        XCTAssertEqual(call.name, ToolDefinition.shellRun.name)
        XCTAssertEqual(try arguments.requiredString("cmd"), "sh '.quillcode/actions/prepare.sh'")
        XCTAssertEqual(arguments.stringDictionary("environment"), [
            "CACHE_DIR": ".cache/quill",
            "QUILL_ENV": "dev"
        ])
        XCTAssertEqual(try arguments.requiredInt("timeoutSeconds"), 120)
    }

    func testLocalEnvironmentActionOmitsOptionalMetadataWhenUnset() throws {
        let action = LocalEnvironmentAction(
            id: "local-env:test",
            title: "Test",
            relativePath: ".quillcode/actions/test.sh",
            command: "sh '.quillcode/actions/test.sh'"
        )

        let arguments = try ToolArguments(
            WorkspaceShellToolCallPlanner.localEnvironmentAction(action).argumentsJSON
        )

        XCTAssertEqual(try arguments.requiredString("cmd"), "sh '.quillcode/actions/test.sh'")
        XCTAssertNil(arguments.stringDictionary("environment"))
        XCTAssertNil(arguments.int("timeoutSeconds"))
    }

    func testWorktreeSetupBuildsBoundedShellToolCall() throws {
        let script = WorktreeSetupScript(
            relativePath: ".quillcode/setup.sh",
            command: "sh '.quillcode/setup.sh'",
            environment: ["QUILL_ENV": "development"],
            timeoutSeconds: 900
        )

        let call = WorkspaceShellToolCallPlanner.worktreeSetupScript(script)
        let arguments = try ToolArguments(call.argumentsJSON)

        XCTAssertEqual(call.name, ToolDefinition.shellRun.name)
        XCTAssertEqual(try arguments.requiredString("cmd"), "sh '.quillcode/setup.sh'")
        XCTAssertEqual(arguments.stringDictionary("environment"), ["QUILL_ENV": "development"])
        XCTAssertEqual(try arguments.requiredInt("timeoutSeconds"), 900)
    }

    func testProjectExtensionUpdateBuildsShellToolCall() throws {
        let manifest = ProjectExtensionManifest(
            id: "plugin:github",
            kind: .plugin,
            name: "GitHub",
            relativePath: ".quillcode/plugins/github.json",
            updateCommand: "git -C .quillcode/plugins/github pull --ff-only",
            updateTimeoutSeconds: 300
        )

        let call = try XCTUnwrap(WorkspaceShellToolCallPlanner.projectExtensionUpdate(manifest))
        let arguments = try ToolArguments(call.argumentsJSON)

        XCTAssertEqual(call.name, ToolDefinition.shellRun.name)
        XCTAssertEqual(
            try arguments.requiredString("cmd"),
            "git -C .quillcode/plugins/github pull --ff-only"
        )
        XCTAssertEqual(try arguments.requiredInt("timeoutSeconds"), 300)
        XCTAssertNil(arguments.stringDictionary("environment"))
    }

    func testProjectExtensionInstallBuildsShellToolCall() throws {
        let manifest = ProjectExtensionManifest(
            id: "plugin:github",
            kind: .plugin,
            name: "GitHub",
            relativePath: ".quillcode/plugins/github.json",
            installCommand: "git clone https://github.com/Lore-Hex/quillcode-github .quillcode/plugins/github",
            installTimeoutSeconds: 600
        )

        let call = try XCTUnwrap(WorkspaceShellToolCallPlanner.projectExtensionInstall(manifest))
        let arguments = try ToolArguments(call.argumentsJSON)

        XCTAssertEqual(call.name, ToolDefinition.shellRun.name)
        XCTAssertEqual(
            try arguments.requiredString("cmd"),
            "git clone https://github.com/Lore-Hex/quillcode-github .quillcode/plugins/github"
        )
        XCTAssertEqual(try arguments.requiredInt("timeoutSeconds"), 600)
        XCTAssertNil(arguments.stringDictionary("environment"))
    }

    func testProjectExtensionInstallRejectsBlankCommand() {
        let manifest = ProjectExtensionManifest(
            id: "plugin:blank",
            kind: .plugin,
            name: "Blank",
            relativePath: ".quillcode/plugins/blank.json",
            installCommand: " \n\t ",
            installTimeoutSeconds: 300
        )

        XCTAssertNil(WorkspaceShellToolCallPlanner.projectExtensionInstall(manifest))
    }

    func testProjectExtensionUpdateRejectsBlankCommand() {
        let manifest = ProjectExtensionManifest(
            id: "plugin:blank",
            kind: .plugin,
            name: "Blank",
            relativePath: ".quillcode/plugins/blank.json",
            updateCommand: " \n\t ",
            updateTimeoutSeconds: 300
        )

        XCTAssertNil(WorkspaceShellToolCallPlanner.projectExtensionUpdate(manifest))
    }
}
