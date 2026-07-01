import XCTest
@testable import QuillCodePersistence

final class FileSecretStoreTests: PersistenceTestCase {
    func testFileSecretStoreRoundTrips() throws {
        let store = try FileSecretStore(directory: makeTempDirectory())

        try store.write("sk-test", for: "trustedrouter:key")

        XCTAssertEqual(try store.read("trustedrouter:key"), "sk-test")
        try store.delete("trustedrouter:key")
        XCTAssertNil(try store.read("trustedrouter:key"))
    }

    func testFileSecretStoreUsesPrivatePermissions() throws {
        let root = try makeTempDirectory()
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        let store = FileSecretStore(directory: root)

        try store.write("sk-test", for: "trustedrouter:key")

        XCTAssertEqual(try posixPermissions(at: root), 0o700)
        let secretFile = try XCTUnwrap(FileManager.default.contentsOfDirectory(atPath: root.path).first)
        XCTAssertEqual(try posixPermissions(at: root.appendingPathComponent(secretFile)), 0o600)
    }

    func testFileSecretStoreSanitizesKeysToSingleFileNames() throws {
        let root = try makeTempDirectory()
        let store = FileSecretStore(directory: root)

        try store.write("sk-test", for: "../trustedrouter/key:prod")

        XCTAssertEqual(try store.read("../trustedrouter/key:prod"), "sk-test")
        let files = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertEqual(files, ["_trustedrouter_key_prod"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("trustedrouter").path))
    }
}
