import XCTest
@testable import QuillCodeApp

final class WorkspaceProjectConfigurationLoaderTests: XCTestCase {
    func testParseLoadsAdditionalActionDirectoriesAndMaxActions() {
        let configuration = WorkspaceProjectConfigurationLoader.parse(
            """
            # Defaults stay enabled; project config adds more action roots.
            local_action_directory = "scripts/quill-actions"
            local_action_directories = ["tools/actions", "scripts/quill-actions"]
            max_local_actions = 24

            [local_actions]
            directory = "ci/tasks"
            directories = ["support/actions"]
            max = 32

            [hooks]
            before_agent_run_directory = "scripts/before-agent"
            before_agent_run_directories = ["ci/before"]
            after_agent_run_directory = "scripts/after-agent"
            after_agent_run_directories = ["ci/after"]
            max = 12
            """
        )

        XCTAssertEqual(configuration.localActionDirectories, [
            ".quillcode/actions",
            ".quillcode/local-env",
            "scripts/quill-actions",
            "tools/actions",
            "ci/tasks",
            "support/actions"
        ])
        XCTAssertEqual(configuration.maxLocalActions, 32)
        XCTAssertEqual(configuration.beforeAgentRunHookDirectories, [
            ".quillcode/hooks/before-agent-run",
            "scripts/before-agent",
            "ci/before"
        ])
        XCTAssertEqual(configuration.afterAgentRunHookDirectories, [
            ".quillcode/hooks/after-agent-run",
            "scripts/after-agent",
            "ci/after"
        ])
        XCTAssertEqual(configuration.maxRunHooks, 12)
    }

    func testParseRejectsUnsafeDirectoriesAndInvalidMax() {
        let configuration = WorkspaceProjectConfigurationLoader.parse(
            """
            local_action_directory = scripts/bare
            local_action_directories = ["/tmp/actions", "../escape", "valid/actions", "also/valid"]
            max_local_actions = 1000

            [hooks]
            before_agent_run_directories = ["/tmp/hooks", "../escape", "valid/before"]
            after_agent_run_directories = ["valid/after"]
            max = 1000
            """
        )

        XCTAssertEqual(configuration.localActionDirectories, [
            ".quillcode/actions",
            ".quillcode/local-env",
            "valid/actions",
            "also/valid"
        ])
        XCTAssertEqual(configuration.maxLocalActions, LocalEnvironmentActionLoader.maxActions)
        XCTAssertEqual(configuration.beforeAgentRunHookDirectories, [
            ".quillcode/hooks/before-agent-run",
            "valid/before"
        ])
        XCTAssertEqual(configuration.afterAgentRunHookDirectories, [
            ".quillcode/hooks/after-agent-run",
            "valid/after"
        ])
        XCTAssertEqual(configuration.maxRunHooks, ProjectRunHookLoader.maxHooks)
    }

    func testParseLoadsWorktreeSetupScriptOverrides() {
        let configuration = WorkspaceProjectConfigurationLoader.parse(
            """
            [worktree_setup]
            script = "tools/setup/default.sh"
            macos = "tools/setup/apple.sh"
            linux = "tools/setup/linux.sh"
            """
        )

        XCTAssertEqual(configuration.worktreeSetup, WorktreeSetupConfiguration(
            scriptPath: "tools/setup/default.sh",
            macOSScriptPath: "tools/setup/apple.sh",
            linuxScriptPath: "tools/setup/linux.sh",
            isExplicitlyConfigured: true
        ))
        XCTAssertTrue(configuration.worktreeSetup.isValid)
    }

    func testParseRejectsUnsafeWorktreeSetupScriptOverrides() {
        let configuration = WorkspaceProjectConfigurationLoader.parse(
            """
            [worktree_setup]
            script = "../escape.sh"
            macos = "/tmp/setup.sh"
            linux = "tools/setup.txt"
            """
        )

        XCTAssertTrue(configuration.worktreeSetup.isExplicitlyConfigured)
        XCTAssertFalse(configuration.worktreeSetup.isValid)
    }

    func testParseRejectsMalformedExplicitWorktreeSetupValue() {
        let configuration = WorkspaceProjectConfigurationLoader.parse(
            """
            [worktree_setup]
            script = scripts/setup.sh
            """
        )

        XCTAssertTrue(configuration.worktreeSetup.isExplicitlyConfigured)
        XCTAssertFalse(configuration.worktreeSetup.isValid)
    }

    func testParseLoadsNamedLocalEnvironmentsAndDefault() throws {
        let configuration = WorkspaceProjectConfigurationLoader.parse(
            """
            [worktree_setup]
            default_environment = "development"

            [local_environments.development]
            title = "Development"
            description = "Install dependencies for app development."
            script = "tools/environments/dev.sh"
            macos = "tools/environments/dev-macos.sh"
            linux = "tools/environments/dev-linux.sh"

            [local_environments.ci]
            title = "CI"
            """
        )

        XCTAssertEqual(configuration.defaultLocalEnvironmentID, "development")
        XCTAssertEqual(configuration.localEnvironments.map(\.id), ["development", "ci"])
        let development = try XCTUnwrap(configuration.localEnvironments.first)
        XCTAssertEqual(development.title, "Development")
        XCTAssertEqual(development.description, "Install dependencies for app development.")
        XCTAssertEqual(development.setup.scriptPath, "tools/environments/dev.sh")
        XCTAssertEqual(development.setup.macOSScriptPath, "tools/environments/dev-macos.sh")
        XCTAssertEqual(development.setup.linuxScriptPath, "tools/environments/dev-linux.sh")
        XCTAssertEqual(
            configuration.localEnvironments.last?.setup.scriptPath,
            ".quillcode/environments/ci/setup.sh"
        )
    }

    func testParseRejectsUnsafeNamedEnvironmentIDsAndDanglingDefault() {
        let configuration = WorkspaceProjectConfigurationLoader.parse(
            """
            [worktree_setup]
            default_environment = "missing"

            [local_environments.good]
            script = "../escape.sh"

            [local_environments.bad/path]
            title = "Ignored"
            """
        )

        XCTAssertEqual(configuration.localEnvironments.map(\.id), ["good"])
        XCTAssertFalse(try XCTUnwrap(configuration.localEnvironments.first).setup.isValid)
        XCTAssertNil(configuration.defaultLocalEnvironmentID)
    }

    func testLoadBoundsConfigFileToProject() throws {
        let root = try makeQuillCodeTestDirectory()
        let quillDirectory = root.appendingPathComponent(".quillcode")
        try FileManager.default.createDirectory(at: quillDirectory, withIntermediateDirectories: true)
        try """
        [local_actions]
        directory = "scripts/actions"
        max = 2
        """.write(
            to: quillDirectory.appendingPathComponent("config.toml"),
            atomically: true,
            encoding: .utf8
        )

        let configuration = WorkspaceProjectConfigurationLoader.load(from: root)

        XCTAssertEqual(configuration.localActionDirectories, [
            ".quillcode/actions",
            ".quillcode/local-env",
            "scripts/actions"
        ])
        XCTAssertEqual(configuration.maxLocalActions, 2)
        XCTAssertFalse(configuration.worktreeSetup.isExplicitlyConfigured)
        XCTAssertTrue(configuration.worktreeSetup.isValid)
    }
}
