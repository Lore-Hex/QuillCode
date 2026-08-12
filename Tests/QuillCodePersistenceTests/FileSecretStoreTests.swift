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

    func testFileSecretStoreReadsExistingPlaintextEntry() throws {
        let root = try makeTempDirectory()
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        let entry = root.appendingPathComponent("trustedrouter_api_key")
        try Data("existing-secret".utf8).write(to: entry)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: entry.path)

        let value = try FileSecretStore(directory: root).read(QuillSecretKeys.trustedRouterAPIKey)

        XCTAssertEqual(value, "existing-secret")
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

    func testFileSecretStoreRejectsOversizedWriteWithoutReplacingExistingSecret() throws {
        let root = try makeTempDirectory()
        let store = FileSecretStore(directory: root)
        try store.write("existing", for: "trustedrouter:key")

        XCTAssertThrowsError(
            try store.write(
                String(repeating: "x", count: FileSecretStore.maximumValueBytes + 1),
                for: "trustedrouter:key"
            )
        ) { error in
            XCTAssertEqual(
                error as? FileSecretStoreError,
                .valueExceedsSizeLimit(maximumBytes: FileSecretStore.maximumValueBytes)
            )
        }
        XCTAssertEqual(try store.read("trustedrouter:key"), "existing")
    }

    func testFileSecretStoreRejectsOversizedReadBeforeLoadingPayload() throws {
        let root = try makeTempDirectory()
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        let secret = root.appendingPathComponent("trustedrouter_key")
        try Data(count: FileSecretStore.maximumValueBytes + 1).write(to: secret)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: secret.path)

        XCTAssertThrowsError(try FileSecretStore(directory: root).read("trustedrouter:key")) { error in
            XCTAssertEqual(
                error as? BoundedFileDataError,
                .exceedsSizeLimit(maximumBytes: FileSecretStore.maximumValueBytes)
            )
        }
    }

    func testFileSecretStoreRejectsSymbolicLinkReadAndAtomicallyReplacesLinkOnWrite() throws {
        let parent = try makeTempDirectory()
        let root = parent.appendingPathComponent("secrets", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        let target = parent.appendingPathComponent("outside-secret")
        try Data("outside".utf8).write(to: target)
        let link = root.appendingPathComponent("trustedrouter_key")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let store = FileSecretStore(directory: root)

        XCTAssertThrowsError(try store.read("trustedrouter:key"))
        try store.write("replacement", for: "trustedrouter:key")

        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "outside")
        XCTAssertEqual(try link.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink, false)
        XCTAssertEqual(try store.read("trustedrouter:key"), "replacement")
    }

    func testFileSecretStoreDeleteUnlinksSymbolicLinkWithoutTouchingTarget() throws {
        let parent = try makeTempDirectory()
        let root = parent.appendingPathComponent("secrets", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        let target = parent.appendingPathComponent("outside-secret")
        try Data("outside".utf8).write(to: target)
        let link = root.appendingPathComponent("trustedrouter_key")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        try FileSecretStore(directory: root).delete("trustedrouter:key")

        XCTAssertFalse(FileManager.default.fileExists(atPath: link.path))
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "outside")
    }

    func testFileSecretStoreRejectsHardLinkedReadAndRepairsEntryOnWrite() throws {
        let parent = try makeTempDirectory()
        let root = parent.appendingPathComponent("secrets", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        let target = parent.appendingPathComponent("outside-secret")
        try Data("outside".utf8).write(to: target)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        let entry = root.appendingPathComponent("trustedrouter_key")
        try FileManager.default.linkItem(at: target, to: entry)
        let store = FileSecretStore(directory: root)

        XCTAssertThrowsError(try store.read("trustedrouter:key")) { error in
            XCTAssertEqual(error as? FileSecretStoreError, .unsafeSecretEntry)
        }
        try store.write("replacement", for: "trustedrouter:key")

        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "outside")
        XCTAssertEqual(try store.read("trustedrouter:key"), "replacement")
    }

    func testFileSecretStoreRejectsSymbolicLinkDirectory() throws {
        let parent = try makeTempDirectory()
        let target = parent.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        let link = parent.appendingPathComponent("secrets", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let store = FileSecretStore(directory: link)

        XCTAssertThrowsError(try store.write("secret", for: "trustedrouter:key"))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: target.path).isEmpty)
    }

    func testFileSecretStoreRejectsInvalidUTF8() throws {
        let root = try makeTempDirectory()
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        let secret = root.appendingPathComponent("trustedrouter_key")
        try Data([0xFF]).write(to: secret)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: secret.path)

        XCTAssertThrowsError(try FileSecretStore(directory: root).read("trustedrouter:key")) { error in
            XCTAssertEqual(error as? FileSecretStoreError, .invalidUTF8)
        }
    }

    func testFileSecretStoreAtomicReplacementLeavesOnlyCanonicalEntry() throws {
        let root = try makeTempDirectory()
        let store = FileSecretStore(directory: root)

        for ordinal in 0..<100 {
            try store.write("secret-\(ordinal)", for: "trustedrouter:key")
        }

        XCTAssertEqual(try store.read("trustedrouter:key"), "secret-99")
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: root.path),
            ["trustedrouter_key"]
        )
    }

    func testFileSecretStoreConcurrentReadersObserveOnlyCompleteValues() async throws {
        let root = try makeTempDirectory()
        let store = FileSecretStore(directory: root)
        try store.write("secret-0", for: "trustedrouter:key")

        let allValuesWereComplete = try await withThrowingTaskGroup(of: Bool.self) { group in
            for ordinal in 1...100 {
                group.addTask {
                    try store.write("secret-\(ordinal)", for: "trustedrouter:key")
                    return true
                }
                group.addTask {
                    for _ in 0..<20 {
                        guard let value = try store.read("trustedrouter:key"),
                              value.hasPrefix("secret-"),
                              let ordinal = Int(value.dropFirst("secret-".count)),
                              (0...100).contains(ordinal)
                        else {
                            return false
                        }
                    }
                    return true
                }
            }

            var allValid = true
            for try await result in group {
                allValid = allValid && result
            }
            return allValid
        }

        XCTAssertTrue(allValuesWereComplete)
        XCTAssertFalse(try XCTUnwrap(store.read("trustedrouter:key")).isEmpty)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: root.path),
            ["trustedrouter_key"]
        )
    }
}
