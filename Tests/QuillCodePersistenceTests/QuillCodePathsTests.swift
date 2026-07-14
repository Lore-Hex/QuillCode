import XCTest
@testable import QuillCodePersistence

final class QuillCodePathsTests: PersistenceTestCase {
    func testEnsureCreatesDurableWorkspaceDirectories() throws {
        let home = try makeTempDirectory()
            .appendingPathComponent(".quillcode")
        let paths = QuillCodePaths(home: home)

        try paths.ensure()

        for directory in [
            paths.threadsDirectory,
            paths.subagentThreadsDirectory,
            paths.subagentApprovalPayloadsDirectory,
            paths.attachmentsDirectory,
            paths.memoriesDirectory,
            paths.worktreeSnapshotsDirectory,
            paths.worktreesDirectory,
            paths.secretsDirectory,
            paths.pluginDataDirectory,
            paths.subagentSessionsDirectory,
            paths.importsDirectory
        ] {
            var isDirectory: ObjCBool = false
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory))
            XCTAssertTrue(isDirectory.boolValue)
        }
        XCTAssertEqual(try posixPermissions(at: paths.subagentApprovalPayloadsDirectory), 0o700)
        XCTAssertEqual(try posixPermissions(at: paths.pluginDataDirectory), 0o700)
        XCTAssertEqual(try posixPermissions(at: paths.importsDirectory), 0o700)
    }

    func testPluginDataDirectoriesAreStablePrivateAndWorkspaceScoped() throws {
        let home = try makeTempDirectory().appendingPathComponent(".quillcode")
        let firstWorkspace = try makeTempDirectory()
        let secondWorkspace = try makeTempDirectory()
        let paths = QuillCodePaths(home: home)
        try paths.ensure()

        let first = try ProjectPluginDataDirectoryLocator.directoryURL(
            baseDirectory: paths.pluginDataDirectory,
            workspaceRoot: firstWorkspace,
            pluginID: "plugin:demo"
        )
        let repeated = try ProjectPluginDataDirectoryLocator.directoryURL(
            baseDirectory: paths.pluginDataDirectory,
            workspaceRoot: firstWorkspace,
            pluginID: "plugin:demo"
        )
        let otherPlugin = try ProjectPluginDataDirectoryLocator.directoryURL(
            baseDirectory: paths.pluginDataDirectory,
            workspaceRoot: firstWorkspace,
            pluginID: "plugin:other"
        )
        let otherWorkspace = try ProjectPluginDataDirectoryLocator.directoryURL(
            baseDirectory: paths.pluginDataDirectory,
            workspaceRoot: secondWorkspace,
            pluginID: "plugin:demo"
        )

        XCTAssertEqual(first, repeated)
        XCTAssertNotEqual(first, otherPlugin)
        XCTAssertNotEqual(first, otherWorkspace)
        XCTAssertTrue(first.path.hasPrefix(paths.pluginDataDirectory.path + "/"))
        XCTAssertEqual(try posixPermissions(at: first), 0o700)
    }

    func testPluginDataDirectoryRejectsSymlinkedBaseDirectory() throws {
        let root = try makeTempDirectory()
        let actualDataDirectory = root.appendingPathComponent("actual-plugin-data")
        let linkedDataDirectory = root.appendingPathComponent("plugin-data")
        try FileManager.default.createDirectory(at: actualDataDirectory, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(
            at: linkedDataDirectory,
            withDestinationURL: actualDataDirectory
        )

        XCTAssertThrowsError(try ProjectPluginDataDirectoryLocator.directoryURL(
            baseDirectory: linkedDataDirectory,
            workspaceRoot: try makeTempDirectory(),
            pluginID: "plugin:demo"
        ))
    }
}
