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
            paths.attachmentsDirectory,
            paths.memoriesDirectory,
            paths.worktreeSnapshotsDirectory,
            paths.managedWorktreesDirectory,
            paths.secretsDirectory,
            paths.permissionsDirectory
        ] {
            var isDirectory: ObjCBool = false
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory))
            XCTAssertTrue(isDirectory.boolValue)
            let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        }
    }
}
