import XCTest
@testable import QuillCodePersistence

#if canImport(Security)
import Security
#endif

final class PlatformSecretStoreTests: PersistenceTestCase {
    func testIsolatedFactoryUsesItsPrivateFileStore() throws {
        let paths = QuillCodePaths(home: try makeTempDirectory())
        try paths.ensure()
        let store = QuillSecretStoreFactory.make(for: paths)

        try store.write("isolated-secret", for: QuillSecretKeys.trustedRouterAPIKey)

        XCTAssertEqual(
            try FileSecretStore(directory: paths.secretsDirectory)
                .read(QuillSecretKeys.trustedRouterAPIKey),
            "isolated-secret"
        )
    }

    #if canImport(Security)
    func testFactoryRequiresCanonicalHomeAndMatchingDeveloperIDSignatureForKeychain() throws {
        XCTAssertTrue(
            QuillSecretStoreFactory.make(
                for: QuillCodePaths(),
                signingTeamIdentifier: nil,
                runtimeSigningTeamIdentifier: nil
            ) is FileSecretStore
        )
        XCTAssertTrue(
            QuillSecretStoreFactory.make(
                for: QuillCodePaths(),
                signingTeamIdentifier: "lowercase1",
                runtimeSigningTeamIdentifier: "lowercase1"
            ) is FileSecretStore
        )
        XCTAssertTrue(
            QuillSecretStoreFactory.make(
                for: QuillCodePaths(),
                signingTeamIdentifier: "A1B2C3D4E5",
                runtimeSigningTeamIdentifier: nil
            ) is FileSecretStore
        )
        XCTAssertTrue(
            QuillSecretStoreFactory.make(
                for: QuillCodePaths(),
                signingTeamIdentifier: "A1B2C3D4E5",
                runtimeSigningTeamIdentifier: "OTHER12345"
            ) is FileSecretStore
        )
        XCTAssertTrue(
            QuillSecretStoreFactory.make(
                for: QuillCodePaths(),
                signingTeamIdentifier: "A1B2C3D4E5",
                runtimeSigningTeamIdentifier: "A1B2C3D4E5"
            ) is LegacyMigratingSecretStore
        )
        XCTAssertTrue(
            QuillSecretStoreFactory.make(
                for: QuillCodePaths(home: try makeTempDirectory()),
                signingTeamIdentifier: "A1B2C3D4E5",
                runtimeSigningTeamIdentifier: "A1B2C3D4E5"
            ) is FileSecretStore
        )
    }

    func testRuntimeSigningIdentityReturnsOnlyADeveloperTeamIdentifier() {
        let teamIdentifier = MacOSCodeSigningIdentity.currentTeamIdentifier

        if let teamIdentifier {
            XCTAssertEqual(teamIdentifier.utf8.count, 10)
            XCTAssertTrue(teamIdentifier.utf8.allSatisfy { byte in
                (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
                    || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
            })
        }
    }
    #endif

    func testLegacyReadMigratesOnlyAfterPrimaryWriteSucceeds() throws {
        let primary = try makePrivateSecretStore()
        let legacy = try makePrivateSecretStore()
        let store = LegacyMigratingSecretStore(primary: primary, legacy: legacy)
        try legacy.write("legacy-secret", for: "credential")

        XCTAssertEqual(try store.read("credential"), "legacy-secret")
        XCTAssertEqual(try primary.read("credential"), "legacy-secret")
        XCTAssertNil(try legacy.read("credential"))
    }

    func testPrimaryValueWinsAndRetiresStaleLegacyCopy() throws {
        let primary = try makePrivateSecretStore()
        let legacy = try makePrivateSecretStore()
        let store = LegacyMigratingSecretStore(primary: primary, legacy: legacy)
        try primary.write("current-secret", for: "credential")
        try legacy.write("stale-secret", for: "credential")

        XCTAssertEqual(try store.read("credential"), "current-secret")
        XCTAssertNil(try legacy.read("credential"))
    }

    func testWriteStoresPrimaryAndRetiresLegacyCopy() throws {
        let primary = try makePrivateSecretStore()
        let legacy = try makePrivateSecretStore()
        let store = LegacyMigratingSecretStore(primary: primary, legacy: legacy)
        try legacy.write("legacy-secret", for: "credential")

        try store.write("replacement-secret", for: "credential")

        XCTAssertEqual(try primary.read("credential"), "replacement-secret")
        XCTAssertNil(try legacy.read("credential"))
    }

    func testFailedPrimaryWritePreservesLegacyCredential() throws {
        let primary = try makePrivateSecretStore()
        let legacy = try makePrivateSecretStore()
        let store = LegacyMigratingSecretStore(primary: primary, legacy: legacy)
        try legacy.write("legacy-secret", for: "credential")

        XCTAssertThrowsError(try store.write(
            String(repeating: "x", count: FileSecretStore.maximumValueBytes + 1),
            for: "credential"
        ))

        XCTAssertNil(try primary.read("credential"))
        XCTAssertEqual(try legacy.read("credential"), "legacy-secret")
    }

    func testDeleteRetiresLegacyBeforePrimary() throws {
        let parent = try makeTempDirectory()
        let primary = FileSecretStore(directory: parent.appendingPathComponent("primary"))
        let actualLegacy = parent.appendingPathComponent("actual-legacy")
        let unsafeLegacy = parent.appendingPathComponent("legacy")
        try FileManager.default.createDirectory(at: actualLegacy, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(
            at: unsafeLegacy,
            withDestinationURL: actualLegacy
        )
        let store = LegacyMigratingSecretStore(
            primary: primary,
            legacy: FileSecretStore(directory: unsafeLegacy)
        )
        try primary.write("protected-secret", for: "credential")

        XCTAssertThrowsError(try store.delete("credential"))

        XCTAssertEqual(try primary.read("credential"), "protected-secret")
    }

    #if canImport(Security)
    func testKeychainStoreRoundTripsWithoutPlaintextFiles() throws {
        let service = "co.lorehex.QuillCowork.tests.\(UUID().uuidString)"
        let key = "credential:\(UUID().uuidString)"
        let store = KeychainSecretStore(service: service)
        defer { try? store.delete(key) }

        XCTAssertNil(try store.read(key))
        try store.write("first-secret", for: key)
        XCTAssertEqual(try store.read(key), "first-secret")

        try store.write("replacement-secret", for: key)
        XCTAssertEqual(try store.read(key), "replacement-secret")

        try store.delete(key)
        XCTAssertNil(try store.read(key))
    }

    func testKeychainStoreRejectsInvalidAndOversizedInputsBeforeMutation() throws {
        let store = KeychainSecretStore(service: "co.lorehex.QuillCowork.tests.\(UUID().uuidString)")

        XCTAssertThrowsError(try store.read("")) { error in
            XCTAssertEqual(error as? KeychainSecretStoreError, .invalidKey)
        }
        XCTAssertThrowsError(try KeychainSecretStore(service: "").read("credential")) { error in
            XCTAssertEqual(error as? KeychainSecretStoreError, .invalidService)
        }
        XCTAssertThrowsError(try store.write(
            String(repeating: "x", count: KeychainSecretStore.maximumValueBytes + 1),
            for: "credential"
        )) { error in
            XCTAssertEqual(
                error as? KeychainSecretStoreError,
                .valueExceedsSizeLimit(maximumBytes: KeychainSecretStore.maximumValueBytes)
            )
        }
    }
    #endif

    private func makePrivateSecretStore() throws -> FileSecretStore {
        let directory = try makeTempDirectory()
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
        return FileSecretStore(directory: directory)
    }
}
