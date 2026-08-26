import Foundation
import XCTest

final class ParityMacOSDistributionSigningGateTests: QuillCodeParityTestCase {
    func testMissingCredentialsKeepTesterSigningUnconfigured() throws {
        let result = try runSigningConfiguration()

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("tester builds will use ad-hoc signing"))
        XCTAssertTrue(result.exportedEnvironment.isEmpty)
        XCTAssertTrue(result.securityLog.isEmpty)
        XCTAssertFalse(result.signingRootExists)
    }

    func testPartialCredentialsFailBeforeCreatingSensitiveFiles() throws {
        let result = try runSigningConfiguration(overrides: [
            "APPLE_DEVELOPER_ID_CERTIFICATE_BASE64": Data("certificate".utf8).base64EncodedString()
        ])

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(result.output.contains("only partially configured"))
        XCTAssertTrue(result.exportedEnvironment.isEmpty)
        XCTAssertTrue(result.securityLog.isEmpty)
        XCTAssertFalse(result.signingRootExists)
    }

    func testMalformedAppleIdentifiersFailBeforeCreatingSensitiveFiles() throws {
        let cases = [
            ("APPLE_TEAM_ID", "lowercase", "APPLE_TEAM_ID must be"),
            ("APPLE_NOTARY_KEY_ID", "short", "APPLE_NOTARY_KEY_ID must be"),
            ("APPLE_NOTARY_ISSUER_ID", "not-a-uuid", "APPLE_NOTARY_ISSUER_ID must be")
        ]

        for (key, value, expectedMessage) in cases {
            var credentials = validCredentials
            credentials[key] = value
            let result = try runSigningConfiguration(overrides: credentials)

            XCTAssertEqual(result.exitCode, 2, "\(key): \(result.output)")
            XCTAssertTrue(result.output.contains(expectedMessage), "\(key): \(result.output)")
            XCTAssertTrue(result.exportedEnvironment.isEmpty, key)
            XCTAssertTrue(result.securityLog.isEmpty, key)
            XCTAssertFalse(result.signingRootExists, key)
        }
    }

    func testSuccessfulConfigurationExportsOnlyOwnedPaths() throws {
        let result = try runSigningConfiguration(overrides: validCredentials)

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("Configured Developer ID signing"))
        XCTAssertTrue(result.exportedEnvironment.contains("QUILLCODE_MACOS_SIGNING_IDENTITY="))
        XCTAssertTrue(result.exportedEnvironment.contains("QUILLCODE_MACOS_SIGNING_TEAM_IDENTIFIER=ABCDE12345"))
        XCTAssertTrue(result.exportedEnvironment.contains("QUILLCODE_MACOS_SIGNING_KEYCHAIN="))
        XCTAssertTrue(result.exportedEnvironment.contains("QUILLCODE_MACOS_NOTARY_KEY_PATH="))
        XCTAssertFalse(result.exportedEnvironment.contains("certificate-password"))
        XCTAssertFalse(result.exportedEnvironment.contains(validCredentials["APPLE_DEVELOPER_ID_CERTIFICATE_BASE64"]!))
        XCTAssertEqual(result.certificateContents, "certificate-bytes")
        XCTAssertEqual(result.notaryKeyContents, "notary-key-bytes")
        XCTAssertEqual(result.certificatePermissions, 0o600)
        XCTAssertEqual(result.notaryKeyPermissions, 0o600)
        XCTAssertTrue(result.securityLog.contains("create-keychain"))
        XCTAssertTrue(result.securityLog.contains("find-identity"))
        XCTAssertTrue(
            result.securityLog.contains("list-keychains -d user -s"),
            "the signing keychain must join the search list or codesign cannot find the identity"
        )
        XCTAssertTrue(
            result.securityLog.contains("login.keychain-db"),
            "the runner's existing keychains must be preserved in the search list"
        )
        XCTAssertFalse(result.securityLog.contains("delete-keychain"))
        XCTAssertTrue(result.signingRootExists)
    }

    func testImportFailureDeletesKeychainAndDecodedCredentials() throws {
        let result = try runSigningConfiguration(
            overrides: validCredentials,
            importFails: true
        )

        XCTAssertEqual(result.exitCode, 7, result.output)
        XCTAssertTrue(result.securityLog.contains("import"))
        XCTAssertTrue(result.securityLog.contains("delete-keychain"))
        XCTAssertTrue(result.exportedEnvironment.isEmpty)
        XCTAssertFalse(result.signingRootExists)
        XCTAssertNil(result.certificateContents)
        XCTAssertNil(result.notaryKeyContents)
    }

    func testImportedIdentityMustBelongToConfiguredTeam() throws {
        var credentials = validCredentials
        credentials["APPLE_DEVELOPER_ID_APPLICATION_IDENTITY"] = "IDENTITY-HASH"
        let result = try runSigningConfiguration(
            overrides: credentials,
            identityLine: #"1) IDENTITY-HASH "Developer ID Application: Quill Cowork (ZZZZZ99999)""#
        )

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(result.output.contains("configured Apple team does not own"))
        XCTAssertTrue(result.securityLog.contains("delete-keychain"))
        XCTAssertTrue(result.exportedEnvironment.isEmpty)
        XCTAssertFalse(result.signingRootExists)
    }

    func testUnreadableSearchListNeverReplacesTheRunnersKeychains() throws {
        let result = try runSigningConfiguration(
            overrides: validCredentials,
            listKeychainsFails: true
        )

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(result.output.contains("refusing to replace it"), result.output)
        // The whole point: a failed read must not narrow the search list to
        // just this temporary keychain, which cleanup then deletes.
        XCTAssertFalse(result.securityLog.contains("list-keychains -d user -s"), result.securityLog)
        XCTAssertTrue(result.exportedEnvironment.isEmpty)
        XCTAssertFalse(result.signingRootExists)
    }

    func testSilentlyDroppedKeychainsFailRatherThanStrandingTheRunner() throws {
        // security omits arguments it cannot open and still reports success,
        // so the written list can be shorter than requested. If every prior
        // entry vanishes, cleanup would leave the runner with no login
        // keychain at all -- fail instead.
        let result = try runSigningConfiguration(
            overrides: validCredentials,
            dropsExistingKeychain: true
        )

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(result.output.contains("pre-existing keychain"), result.output)
        // The stub drops that entry on the restore write too, so the script
        // must report the failure honestly rather than claim success.
        XCTAssertTrue(
            result.output.contains("could not fully restore"),
            "an unrestorable list must be reported, not silently accepted: \(result.output)"
        )
        XCTAssertTrue(result.exportedEnvironment.isEmpty)
        XCTAssertFalse(result.signingRootExists)
    }

    private struct SigningResult {
        var exitCode: Int32
        var output: String
        var exportedEnvironment: String
        var securityLog: String
        var signingRootExists: Bool
        var certificateContents: String?
        var notaryKeyContents: String?
        var certificatePermissions: Int?
        var notaryKeyPermissions: Int?
    }

    private func runSigningConfiguration(
        overrides: [String: String] = [:],
        importFails: Bool = false,
        listKeychainsFails: Bool = false,
        dropsExistingKeychain: Bool = false,
        identityLine: String = #"1) ABCDEF "Developer ID Application: Quill Cowork (ABCDE12345)""#
    ) throws -> SigningResult {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-signing-configuration-tests")
            .appendingPathComponent(UUID().uuidString)
        let binDirectory = temporaryDirectory.appendingPathComponent("bin")
        let runnerTemp = temporaryDirectory.appendingPathComponent("runner")
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: runnerTemp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let securityURL = binDirectory.appendingPathComponent("security")
        let securityLogURL = temporaryDirectory.appendingPathComponent("security.log")
        let githubEnvironmentURL = temporaryDirectory.appendingPathComponent("github.env")
        try fakeSecurity.write(to: securityURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: securityURL.path)
        try Data().write(to: githubEnvironmentURL)

        let outputPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            Self.packageRoot()
                .appendingPathComponent("scripts")
                .appendingPathComponent("configure-macos-distribution-signing.sh")
                .path
        ]
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(binDirectory.path):\(environment["PATH"] ?? "")"
        environment["RUNNER_TEMP"] = runnerTemp.path
        environment["GITHUB_ENV"] = githubEnvironmentURL.path
        environment["SIGNING_TEST_SECURITY_LOG"] = securityLogURL.path
        environment["SIGNING_TEST_IMPORT_FAILS"] = importFails ? "true" : "false"
        environment["SIGNING_TEST_LIST_KEYCHAINS_FAILS"] = listKeychainsFails ? "true" : "false"
        // A real file on disk: the script only keeps search-list entries that
        // exist, so a fictional path would make these assertions vacuous.
        let existingKeychain = temporaryDirectory.appendingPathComponent("login.keychain-db")
        try Data().write(to: existingKeychain)
        environment["SIGNING_TEST_EXISTING_KEYCHAIN"] = existingKeychain.path
        environment["SIGNING_TEST_KEYCHAIN_LIST_STATE"] =
            temporaryDirectory.appendingPathComponent("keychain-list.state").path
        if dropsExistingKeychain {
            environment["SIGNING_TEST_UNOPENABLE"] = existingKeychain.path
        }
        environment["SIGNING_TEST_IDENTITY_LINE"] = identityLine
        for key in Self.credentialKeys {
            environment[key] = ""
        }
        for (key, value) in overrides {
            environment[key] = value
        }
        process.environment = environment

        try process.run()
        process.waitUntilExit()

        let output = String(
            data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let signingRoot = runnerTemp.appendingPathComponent("quill-cowork-signing")
        let certificate = signingRoot.appendingPathComponent("developer-id.p12")
        let notaryKey = signingRoot.appendingPathComponent("AuthKey_KEYID12345.p8")
        return SigningResult(
            exitCode: process.terminationStatus,
            output: output,
            exportedEnvironment: (try? String(contentsOf: githubEnvironmentURL, encoding: .utf8)) ?? "",
            securityLog: (try? String(contentsOf: securityLogURL, encoding: .utf8)) ?? "",
            signingRootExists: FileManager.default.fileExists(atPath: signingRoot.path),
            certificateContents: try? String(contentsOf: certificate, encoding: .utf8),
            notaryKeyContents: try? String(contentsOf: notaryKey, encoding: .utf8),
            certificatePermissions: permissions(at: certificate),
            notaryKeyPermissions: permissions(at: notaryKey)
        )
    }

    private func permissions(at url: URL) -> Int? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let permissions = attributes[.posixPermissions] as? NSNumber
        else { return nil }
        return permissions.intValue
    }

    private var validCredentials: [String: String] {
        [
            "APPLE_DEVELOPER_ID_CERTIFICATE_BASE64": Data("certificate-bytes".utf8).base64EncodedString(),
            "APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD": "certificate-password",
            "APPLE_DEVELOPER_ID_APPLICATION_IDENTITY": "Developer ID Application: Quill Cowork (ABCDE12345)",
            "APPLE_TEAM_ID": "ABCDE12345",
            "APPLE_NOTARY_KEY_ID": "KEYID12345",
            "APPLE_NOTARY_ISSUER_ID": "01234567-89ab-cdef-0123-456789abcdef",
            "APPLE_NOTARY_PRIVATE_KEY_BASE64": Data("notary-key-bytes".utf8).base64EncodedString()
        ]
    }

    private var fakeSecurity: String {
        """
        #!/usr/bin/env bash
        set -euo pipefail
        printf '%s\n' "$*" >> "${SIGNING_TEST_SECURITY_LOG:?}"
        case "$1" in
          create-keychain)
            touch "${@: -1}"
            ;;
          import)
            if [[ "${SIGNING_TEST_IMPORT_FAILS:?}" == "true" ]]; then
              exit 7
            fi
            ;;
          find-identity)
            printf '%s\n' "${SIGNING_TEST_IDENTITY_LINE:?}"
            ;;
          delete-keychain)
            rm -f "${@: -1}"
            ;;
          list-keychains)
            state="${SIGNING_TEST_KEYCHAIN_LIST_STATE:?}"
            if [[ "$*" == *" -s "* ]]; then
              # Model the real write: record the arguments, but drop any entry
              # named in SIGNING_TEST_UNOPENABLE, the way security omits
              # arguments it cannot open as a keychain.
              : > "$state"
              touch "$state.written"   # distinguish "written empty" from "never written"
              shift 4   # past: list-keychains -d user -s
              for candidate in "$@"; do
                if [[ -n "${SIGNING_TEST_UNOPENABLE:-}" && "$candidate" == "$SIGNING_TEST_UNOPENABLE" ]]; then
                  continue
                fi
                printf '    "%s"\n' "$candidate" >> "$state"
              done
            else
              if [[ "${SIGNING_TEST_LIST_KEYCHAINS_FAILS:-false}" == "true" ]]; then
                exit 1
              fi
              if [[ -f "$state.written" ]]; then
                # An empty list after a write is a real, observable outcome --
                # not a reason to fall back to the default.
                cat "$state"
              else
                printf '    "%s"\n' "${SIGNING_TEST_EXISTING_KEYCHAIN:?}"
              fi
            fi
            ;;
          set-keychain-settings|unlock-keychain|set-key-partition-list)
            ;;
          *)
            echo "unexpected security invocation: $*" >&2
            exit 9
            ;;
        esac
        """
    }

    private static let credentialKeys = [
        "APPLE_DEVELOPER_ID_CERTIFICATE_BASE64",
        "APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD",
        "APPLE_DEVELOPER_ID_APPLICATION_IDENTITY",
        "APPLE_TEAM_ID",
        "APPLE_NOTARY_KEY_ID",
        "APPLE_NOTARY_ISSUER_ID",
        "APPLE_NOTARY_PRIVATE_KEY_BASE64"
    ]
}
