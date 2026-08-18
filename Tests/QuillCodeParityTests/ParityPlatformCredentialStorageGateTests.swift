import XCTest

final class ParityPlatformCredentialStorageGateTests: QuillCodeParityTestCase {
    func testProductionCredentialConsumersUseThePlatformFactory() throws {
        let allowedFiles: Set<String> = [
            "Sources/QuillCodePersistence/PlatformSecretStore.swift",
            "Sources/QuillCodePersistence/SecretStore.swift"
        ]
        let offenders = try Self.swiftSourceFiles(in: "Sources").compactMap { file -> String? in
            let relativePath = file.path.replacingOccurrences(
                of: Self.packageRoot().path + "/",
                with: ""
            )
            guard !allowedFiles.contains(relativePath) else { return nil }
            let source = try String(contentsOf: file, encoding: .utf8)
            return source.contains("FileSecretStore(") ? relativePath : nil
        }

        XCTAssertEqual(
            offenders,
            [],
            "Live credential consumers must use QuillSecretStoreFactory: \(offenders)"
        )
    }

    func testKeychainActivationStaysBoundToDeveloperIDMetadataAndMigration() throws {
        let source = try String(
            contentsOf: Self.packageRoot()
                .appendingPathComponent("Sources/QuillCodePersistence/PlatformSecretStore.swift"),
            encoding: .utf8
        )
        let buildScript = try String(
            contentsOf: Self.packageRoot().appendingPathComponent("scripts/build-macos-app.sh"),
            encoding: .utf8
        )

        Self.assertSource(source, containsAll: [
            "QuillCodeSigningTeamIdentifier",
            "isValidTeamIdentifier(signingTeamIdentifier)",
            "static let currentTeamIdentifier = loadCurrentTeamIdentifier()",
            "SecCodeCheckValidity",
            "SecCodeCopyStaticCode",
            "SecCodeCopySigningInformation",
            "runtimeSigningTeamIdentifier == signingTeamIdentifier",
            "LegacyMigratingSecretStore(",
            "KeychainSecretStore(service: paths.secretStorageService)",
            "kSecAttrSynchronizable as String: false",
            "try primary.write(value, for: key)",
            "try legacy.delete(key)"
        ])
        Self.assertSource(buildScript, contains: "QuillCodeSigningTeamIdentifier")
    }
}
