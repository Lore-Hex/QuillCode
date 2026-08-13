import Foundation
import XCTest

final class ParityAppleDistributionCredentialPreflightTests: QuillCodeParityTestCase {
    func testValidCredentialMaterialPassesWithoutPersistingDecodedFiles() throws {
        let fixture = try CredentialFixture()
        defer { fixture.remove() }

        let result = try runPreflight(credentials: fixture.credentials)

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("Validated Apple Developer ID and notarization credential material."))
        XCTAssertFalse(result.output.contains(fixture.password))
        XCTAssertFalse(result.output.contains(fixture.credentials["APPLE_DEVELOPER_ID_CERTIFICATE_BASE64"]!))
        XCTAssertTrue(result.remainingFiles.isEmpty, result.remainingFiles.joined(separator: "\n"))
    }

    func testFingerprintIdentityAndLegacyPKCS12ArchivePass() throws {
        let fixture = try CredentialFixture(usesLegacyPKCS12Encryption: true)
        defer { fixture.remove() }
        var credentials = fixture.credentials
        credentials["APPLE_DEVELOPER_ID_APPLICATION_IDENTITY"] =
            fixture.certificateFingerprint.lowercased()

        let result = try runPreflight(credentials: credentials)

        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("Validated Apple Developer ID"))
        XCTAssertTrue(result.remainingFiles.isEmpty)
    }

    func testMissingCredentialsFailBeforeCreatingDecodedFiles() throws {
        let result = try runPreflight(credentials: [
            "APPLE_TEAM_ID": Self.teamIdentifier
        ])

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(result.output.contains("Missing Apple distribution credentials:"), result.output)
        XCTAssertTrue(result.output.contains("APPLE_DEVELOPER_ID_CERTIFICATE_BASE64"), result.output)
        XCTAssertTrue(result.output.contains("APPLE_NOTARY_PRIVATE_KEY_BASE64"), result.output)
        XCTAssertTrue(result.remainingFiles.isEmpty, result.remainingFiles.joined(separator: "\n"))
    }

    func testMalformedIdentifiersAndIdentityFailBeforeDecoding() throws {
        let fixture = try CredentialFixture()
        defer { fixture.remove() }

        let cases = [
            ("APPLE_TEAM_ID", "lowercase", "APPLE_TEAM_ID must be"),
            ("APPLE_NOTARY_KEY_ID", "SHORT", "APPLE_NOTARY_KEY_ID must be"),
            ("APPLE_NOTARY_ISSUER_ID", "not-a-uuid", "APPLE_NOTARY_ISSUER_ID must be"),
            (
                "APPLE_DEVELOPER_ID_APPLICATION_IDENTITY",
                "Developer ID Application: Quill Cowork (ZZZZZ99999)",
                "must name a Developer ID Application identity owned by APPLE_TEAM_ID"
            )
        ]

        for (key, value, expectedMessage) in cases {
            var credentials = fixture.credentials
            credentials[key] = value
            let result = try runPreflight(credentials: credentials)

            XCTAssertEqual(result.exitCode, 2, "\(key): \(result.output)")
            XCTAssertTrue(result.output.contains(expectedMessage), "\(key): \(result.output)")
            XCTAssertTrue(result.remainingFiles.isEmpty, key)
        }
    }

    func testWrongArchivePasswordAndMismatchedIdentityFailClosed() throws {
        let fixture = try CredentialFixture()
        defer { fixture.remove() }

        var wrongPassword = fixture.credentials
        wrongPassword["APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD"] = "wrong-password"
        let passwordResult = try runPreflight(credentials: wrongPassword)
        XCTAssertEqual(passwordResult.exitCode, 2, passwordResult.output)
        XCTAssertTrue(passwordResult.output.contains("archive or its password is invalid"), passwordResult.output)
        XCTAssertFalse(passwordResult.output.contains("wrong-password"), passwordResult.output)
        XCTAssertTrue(passwordResult.remainingFiles.isEmpty)

        var mismatchedIdentity = fixture.credentials
        mismatchedIdentity["APPLE_DEVELOPER_ID_APPLICATION_IDENTITY"] =
            "Developer ID Application: Another Product (\(Self.teamIdentifier))"
        let identityResult = try runPreflight(credentials: mismatchedIdentity)
        XCTAssertEqual(identityResult.exitCode, 2, identityResult.output)
        XCTAssertTrue(identityResult.output.contains("common name does not match"), identityResult.output)
        XCTAssertTrue(identityResult.remainingFiles.isEmpty)

        var mismatchedFingerprint = fixture.credentials
        mismatchedFingerprint["APPLE_DEVELOPER_ID_APPLICATION_IDENTITY"] =
            String(repeating: "f", count: 40)
        let fingerprintResult = try runPreflight(credentials: mismatchedFingerprint)
        XCTAssertEqual(fingerprintResult.exitCode, 2, fingerprintResult.output)
        XCTAssertTrue(fingerprintResult.output.contains("fingerprint does not match"))
        XCTAssertTrue(fingerprintResult.remainingFiles.isEmpty)
    }

    func testMalformedNotaryKeyFailsClosedAndLeavesNoCredentialMaterial() throws {
        let fixture = try CredentialFixture()
        defer { fixture.remove() }
        var credentials = fixture.credentials
        credentials["APPLE_NOTARY_PRIVATE_KEY_BASE64"] =
            Data("not-a-private-key".utf8).base64EncodedString()

        let result = try runPreflight(credentials: credentials)

        XCTAssertEqual(result.exitCode, 2, result.output)
        XCTAssertTrue(result.output.contains("PKCS#8 PEM format"), result.output)
        XCTAssertTrue(result.remainingFiles.isEmpty, result.remainingFiles.joined(separator: "\n"))

        credentials = fixture.credentials
        credentials["APPLE_NOTARY_PRIVATE_KEY_BASE64"] = "!!!!"
        let invalidBase64Result = try runPreflight(credentials: credentials)
        XCTAssertEqual(invalidBase64Result.exitCode, 2, invalidBase64Result.output)
        XCTAssertTrue(invalidBase64Result.output.contains("is not canonical base64"))
        XCTAssertTrue(invalidBase64Result.remainingFiles.isEmpty)

        credentials = fixture.credentials
        credentials["APPLE_NOTARY_PRIVATE_KEY_BASE64"] = "YR=="
        let noncanonicalBase64Result = try runPreflight(credentials: credentials)
        XCTAssertEqual(noncanonicalBase64Result.exitCode, 2, noncanonicalBase64Result.output)
        XCTAssertTrue(noncanonicalBase64Result.output.contains("is not canonical base64"))
        XCTAssertTrue(noncanonicalBase64Result.remainingFiles.isEmpty)
    }

    func testExpiringAndNonCodeSigningCertificatesFailClosed() throws {
        let expiringFixture = try CredentialFixture(certificateValidityDays: 1)
        defer { expiringFixture.remove() }
        let expiringResult = try runPreflight(credentials: expiringFixture.credentials)
        XCTAssertEqual(expiringResult.exitCode, 2, expiringResult.output)
        XCTAssertTrue(expiringResult.output.contains("expired or expires within seven days"))
        XCTAssertTrue(expiringResult.remainingFiles.isEmpty)

        let wrongUsageFixture = try CredentialFixture(includesCodeSigningUsage: false)
        defer { wrongUsageFixture.remove() }
        let wrongUsageResult = try runPreflight(credentials: wrongUsageFixture.credentials)
        XCTAssertEqual(wrongUsageResult.exitCode, 2, wrongUsageResult.output)
        XCTAssertTrue(wrongUsageResult.output.contains("not valid for code signing"))
        XCTAssertTrue(wrongUsageResult.remainingFiles.isEmpty)
    }

    func testWrongCurveAndOversizedCredentialsFailClosed() throws {
        let wrongCurveFixture = try CredentialFixture(notaryCurve: "P-384")
        defer { wrongCurveFixture.remove() }
        let wrongCurveResult = try runPreflight(credentials: wrongCurveFixture.credentials)
        XCTAssertEqual(wrongCurveResult.exitCode, 2, wrongCurveResult.output)
        XCTAssertTrue(wrongCurveResult.output.contains("must use the P-256 elliptic curve"))
        XCTAssertTrue(wrongCurveResult.remainingFiles.isEmpty)

        let validFixture = try CredentialFixture()
        defer { validFixture.remove() }
        var oversizedCredentials = validFixture.credentials
        oversizedCredentials["APPLE_NOTARY_PRIVATE_KEY_BASE64"] =
            String(repeating: "A", count: 64 * 1024 + 1)
        let oversizedResult = try runPreflight(credentials: oversizedCredentials)
        XCTAssertEqual(oversizedResult.exitCode, 2, oversizedResult.output)
        XCTAssertTrue(oversizedResult.output.contains("exceeds the credential size limit"))
        XCTAssertTrue(oversizedResult.remainingFiles.isEmpty)
    }

    func testStableWorkflowRunsMaterialPreflightBeforeCIWaitAndPackaging() throws {
        let workflow = try Self.workflowText(named: "download-builds.yml")
        Self.assertSource(workflow, containsAll: [
            "Validate stable Apple distribution credentials",
            "if: github.ref_type == 'tag' && startsWith(github.ref_name, 'v')",
            "scripts/validate-apple-distribution-credentials.sh",
            "APPLE_DEVELOPER_ID_CERTIFICATE_BASE64: ${{ secrets.APPLE_DEVELOPER_ID_CERTIFICATE_BASE64 }}",
            "APPLE_NOTARY_PRIVATE_KEY_BASE64: ${{ secrets.APPLE_NOTARY_PRIVATE_KEY_BASE64 }}"
        ])
        let preflight = try XCTUnwrap(
            workflow.range(of: "scripts/validate-apple-distribution-credentials.sh")
        )
        let ciWait = try XCTUnwrap(workflow.range(of: "scripts/wait-for-successful-ci.sh"))
        let macOSJob = try XCTUnwrap(workflow.range(of: "  macos:"))
        XCTAssertLessThan(preflight.lowerBound, ciWait.lowerBound)
        XCTAssertLessThan(preflight.lowerBound, macOSJob.lowerBound)
    }

    private struct PreflightResult {
        let exitCode: Int32
        let output: String
        let remainingFiles: [String]
    }

    private func runPreflight(credentials: [String: String]) throws -> PreflightResult {
        let runnerTemp = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-apple-credential-preflight-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: runnerTemp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: runnerTemp) }

        let outputPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            Self.packageRoot()
                .appendingPathComponent("scripts")
                .appendingPathComponent("validate-apple-distribution-credentials.sh")
                .path
        ]
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        var environment = ProcessInfo.processInfo.environment
        environment["RUNNER_TEMP"] = runnerTemp.path
        for key in Self.credentialKeys {
            environment[key] = ""
        }
        for (key, value) in credentials {
            environment[key] = value
        }
        process.environment = environment

        try process.run()
        process.waitUntilExit()

        let remainingFiles = try FileManager.default.contentsOfDirectory(
            atPath: runnerTemp.path
        ).sorted()
        return PreflightResult(
            exitCode: process.terminationStatus,
            output: String(
                data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? "",
            remainingFiles: remainingFiles
        )
    }

    private final class CredentialFixture {
        let directory: URL
        let password = "certificate-password"
        let certificateFingerprint: String
        let credentials: [String: String]

        init(
            certificateValidityDays: Int = 30,
            includesCodeSigningUsage: Bool = true,
            notaryCurve: String = "P-256",
            usesLegacyPKCS12Encryption: Bool = false
        ) throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("quillcode-apple-credential-fixtures")
                .appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let certificateKey = directory.appendingPathComponent("certificate-key.pem")
            let certificate = directory.appendingPathComponent("certificate.pem")
            let archive = directory.appendingPathComponent("developer-id.p12")
            let notaryECKey = directory.appendingPathComponent("notary-ec.pem")
            let notaryPKCS8Key = directory.appendingPathComponent(
                "AuthKey_\(ParityAppleDistributionCredentialPreflightTests.keyIdentifier).p8"
            )
            var certificateArguments = [
                "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                "-keyout", certificateKey.path,
                "-out", certificate.path,
                "-days", String(certificateValidityDays),
                "-subj",
                "/C=US/O=Lore Hex Corp/OU=\(ParityAppleDistributionCredentialPreflightTests.teamIdentifier)" +
                    "/CN=\(ParityAppleDistributionCredentialPreflightTests.identity)" +
                    "/UID=\(ParityAppleDistributionCredentialPreflightTests.teamIdentifier)"
            ]
            if includesCodeSigningUsage {
                certificateArguments += ["-addext", "extendedKeyUsage=codeSigning"]
            }
            try Self.runOpenSSL(certificateArguments)
            let archiveArguments = [
                "pkcs12", "-export",
                "-out", archive.path,
                "-inkey", certificateKey.path,
                "-in", certificate.path,
                "-name", ParityAppleDistributionCredentialPreflightTests.identity,
                "-passout", "pass:\(password)"
            ]
            if usesLegacyPKCS12Encryption {
                do {
                    try Self.runOpenSSL(archiveArguments + ["-legacy"])
                } catch {
                    // LibreSSL has legacy Keychain-compatible defaults but no -legacy shorthand.
                    try Self.runOpenSSL(archiveArguments)
                }
            } else {
                try Self.runOpenSSL(archiveArguments)
            }
            try Self.runOpenSSL([
                "genpkey", "-algorithm", "EC",
                "-pkeyopt", "ec_paramgen_curve:\(notaryCurve)",
                "-out", notaryECKey.path
            ])
            try Self.runOpenSSL([
                "pkcs8", "-topk8", "-nocrypt",
                "-in", notaryECKey.path,
                "-out", notaryPKCS8Key.path
            ])

            certificateFingerprint = try Self.openSSLOutput([
                "x509", "-in", certificate.path, "-noout", "-fingerprint", "-sha1"
            ])
            .split(separator: "=", maxSplits: 1)
            .last
            .map(String.init)?
            .replacingOccurrences(of: ":", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard certificateFingerprint.count == 40 else {
                throw NSError(
                    domain: "ParityAppleDistributionCredentialPreflightTests",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "OpenSSL returned an invalid certificate fingerprint"]
                )
            }

            credentials = [
                "APPLE_DEVELOPER_ID_CERTIFICATE_BASE64":
                    try Data(contentsOf: archive).base64EncodedString(),
                "APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD": password,
                "APPLE_DEVELOPER_ID_APPLICATION_IDENTITY":
                    ParityAppleDistributionCredentialPreflightTests.identity,
                "APPLE_TEAM_ID": ParityAppleDistributionCredentialPreflightTests.teamIdentifier,
                "APPLE_NOTARY_KEY_ID": ParityAppleDistributionCredentialPreflightTests.keyIdentifier,
                "APPLE_NOTARY_ISSUER_ID": "01234567-89ab-cdef-0123-456789abcdef",
                "APPLE_NOTARY_PRIVATE_KEY_BASE64":
                    try Data(contentsOf: notaryPKCS8Key).base64EncodedString()
            ]
        }

        func remove() {
            try? FileManager.default.removeItem(at: directory)
        }

        private static func runOpenSSL(_ arguments: [String]) throws {
            _ = try openSSLOutput(arguments)
        }

        private static func openSSLOutput(_ arguments: [String]) throws -> String {
            let output = Pipe()
            let errorOutput = Pipe()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["openssl"] + arguments
            process.standardOutput = output
            process.standardError = errorOutput
            try process.run()
            process.waitUntilExit()
            let outputData = output.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorOutput.fileHandleForReading.readDataToEndOfFile()
            guard process.terminationStatus == 0 else {
                let diagnostic = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                throw NSError(
                    domain: "ParityAppleDistributionCredentialPreflightTests",
                    code: Int(process.terminationStatus),
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "OpenSSL \(arguments.first ?? "command") failed: \(diagnostic)"
                    ]
                )
            }
            return String(
                data: outputData,
                encoding: .utf8
            ) ?? ""
        }
    }

    private static let teamIdentifier = "ABCDE12345"
    private static let keyIdentifier = "KEYID12345"
    private static let identity = "Developer ID Application: Quill Cowork (ABCDE12345)"
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
