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
    }

    func testParseRejectsUnsafeDirectoriesAndInvalidMax() {
        let configuration = WorkspaceProjectConfigurationLoader.parse(
            """
            local_action_directory = scripts/bare
            local_action_directories = ["/tmp/actions", "../escape", "valid/actions", "also/valid"]
            max_local_actions = 1000
            """
        )

        XCTAssertEqual(configuration.localActionDirectories, [
            ".quillcode/actions",
            ".quillcode/local-env",
            "valid/actions",
            "also/valid"
        ])
        XCTAssertEqual(configuration.maxLocalActions, LocalEnvironmentActionLoader.maxActions)
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
    }
}
