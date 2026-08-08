import XCTest
@testable import quill_code_desktop

final class QuillCodeDesktopUpdateSigningTests: XCTestCase {
    func testAdHocTesterManifestCarriesExactPayloadRequirement() throws {
        let configuration = makeConfiguration()

        let result = try QuillCodeDesktopUpdateManifestValidator.validate(
            signingManifest(configuration: configuration),
            configuration: configuration
        )

        guard case .updateAvailable(let release) = result else {
            return XCTFail("Expected an available update")
        }
        XCTAssertEqual(release.signingRequirement, .adHoc)
    }

    func testAdHocMetadataRejectsContradictoryTeamAndNotarizationClaims() {
        let configuration = makeConfiguration()
        let manifests = [
            signingManifest(
                configuration: configuration,
                signingTeamIdentifier: "ABCD123456"
            ),
            signingManifest(configuration: configuration, notarized: true),
            signingManifest(configuration: configuration, codesign: nil),
            signingManifest(configuration: configuration, codesign: "unknown")
        ]

        for manifest in manifests {
            XCTAssertThrowsError(
                try QuillCodeDesktopUpdateManifestValidator.validate(
                    manifest,
                    configuration: configuration
                )
            ) { error in
                XCTAssertEqual(error as? QuillCodeDesktopUpdateError, .wrongSigningIdentity)
            }
        }
    }

    func testAdHocTesterCanUpgradeOnlyToNotarizedDeveloperID() throws {
        let configuration = makeConfiguration()
        let manifest = signingManifest(
            configuration: configuration,
            codesign: "developer-id",
            signingTeamIdentifier: "ABCD123456",
            notarized: true
        )

        let result = try QuillCodeDesktopUpdateManifestValidator.validate(
            manifest,
            configuration: configuration
        )

        guard case .updateAvailable(let release) = result else {
            return XCTFail("Expected an available update")
        }
        XCTAssertEqual(
            release.signingRequirement,
            .developerID(teamIdentifier: "ABCD123456")
        )
    }

    func testDeveloperIDUpgradeRejectsMissingNotarizationAndInvalidTeams() {
        let configuration = makeConfiguration()
        let manifests = [
            signingManifest(
                configuration: configuration,
                codesign: "developer-id",
                signingTeamIdentifier: "ABCD123456",
                notarized: false
            ),
            signingManifest(
                configuration: configuration,
                codesign: "developer-id",
                signingTeamIdentifier: nil,
                notarized: true
            ),
            signingManifest(
                configuration: configuration,
                codesign: "developer-id",
                signingTeamIdentifier: "abcd123456",
                notarized: true
            ),
            signingManifest(
                configuration: configuration,
                codesign: "developer-id",
                signingTeamIdentifier: "TOO-SHORT",
                notarized: true
            )
        ]

        for manifest in manifests {
            XCTAssertThrowsError(
                try QuillCodeDesktopUpdateManifestValidator.validate(
                    manifest,
                    configuration: configuration
                )
            ) { error in
                XCTAssertEqual(error as? QuillCodeDesktopUpdateError, .wrongSigningIdentity)
            }
        }
    }

    func testPinnedTesterRejectsAdHocDowngradeAndDifferentDeveloperTeam() throws {
        var configuration = makeConfiguration()
        configuration.expectedSigningTeamIdentifier = "ABCD123456"

        XCTAssertThrowsError(
            try QuillCodeDesktopUpdateManifestValidator.validate(
                signingManifest(configuration: configuration),
                configuration: configuration
            )
        ) { error in
            XCTAssertEqual(error as? QuillCodeDesktopUpdateError, .wrongSigningIdentity)
        }
        XCTAssertThrowsError(
            try QuillCodeDesktopUpdateManifestValidator.validate(
                signingManifest(
                    configuration: configuration,
                    codesign: "developer-id",
                    signingTeamIdentifier: "OTHER12345",
                    notarized: true
                ),
                configuration: configuration
            )
        ) { error in
            XCTAssertEqual(error as? QuillCodeDesktopUpdateError, .wrongSigningIdentity)
        }

        let result = try QuillCodeDesktopUpdateManifestValidator.validate(
            signingManifest(
                configuration: configuration,
                codesign: "developer-id",
                signingTeamIdentifier: "ABCD123456",
                notarized: true
            ),
            configuration: configuration
        )
        guard case .updateAvailable(let release) = result else {
            return XCTFail("Expected an available update")
        }
        XCTAssertEqual(
            release.signingRequirement,
            .developerID(teamIdentifier: "ABCD123456")
        )
    }

    func testStableChannelRequiresPinnedMatchingDeveloperID() throws {
        var configuration = makeConfiguration()
        configuration.channel = .stable
        configuration.manifestURL = configuration.stableManifestURL

        XCTAssertThrowsError(
            try QuillCodeDesktopUpdateManifestValidator.validate(
                signingManifest(configuration: configuration),
                configuration: configuration
            )
        ) { error in
            XCTAssertEqual(error as? QuillCodeDesktopUpdateError, .unsignedStableUpdate)
        }

        configuration.expectedSigningTeamIdentifier = "ABCD123456"
        let result = try QuillCodeDesktopUpdateManifestValidator.validate(
            signingManifest(
                configuration: configuration,
                codesign: "developer-id",
                signingTeamIdentifier: "ABCD123456",
                notarized: true
            ),
            configuration: configuration
        )
        guard case .updateAvailable(let release) = result else {
            return XCTFail("Expected an available update")
        }
        XCTAssertEqual(
            release.signingRequirement,
            .developerID(teamIdentifier: "ABCD123456")
        )
    }

    func testCodeSignatureMetadataDistinguishesAdHocAndDeveloperID() {
        let adHoc = QuillCodeDesktopCodeSignatureMetadata(codesignOutput: """
        Signature=adhoc
        TeamIdentifier=not set
        """)
        XCTAssertTrue(adHoc.satisfies(.adHoc))
        XCTAssertFalse(adHoc.satisfies(.developerID(teamIdentifier: "ABCD123456")))

        let developerID = QuillCodeDesktopCodeSignatureMetadata(codesignOutput: """
        Authority=Developer ID Application: Lore Hex LLC (ABCD123456)
        Authority=Developer ID Certification Authority
        Authority=Apple Root CA
        TeamIdentifier=ABCD123456
        """)
        XCTAssertTrue(developerID.satisfies(.developerID(teamIdentifier: "ABCD123456")))
        XCTAssertFalse(developerID.satisfies(.developerID(teamIdentifier: "OTHER12345")))
        XCTAssertFalse(developerID.satisfies(.adHoc))
    }

    func testDeveloperIDRequirementRejectsInstallerAuthority() {
        let metadata = QuillCodeDesktopCodeSignatureMetadata(codesignOutput: """
        Authority=Developer ID Installer: Lore Hex LLC (ABCD123456)
        TeamIdentifier=ABCD123456
        """)

        XCTAssertFalse(metadata.satisfies(.developerID(teamIdentifier: "ABCD123456")))
    }
}

private func signingManifest(
    configuration: QuillCodeDesktopUpdateConfiguration,
    codesign: String? = "ad-hoc",
    signingTeamIdentifier: String? = nil,
    notarized: Bool? = false
) -> QuillCodeDesktopUpdateManifest {
    let tag = configuration.channel == .stable ? "v0.2.0" : "tester-latest"
    let asset = QuillCodeDesktopUpdateManifest.Asset(
        name: "Quill-Cowork-macOS-arm64.zip",
        kind: "app",
        platform: "macOS",
        arch: "arm64",
        install: "zip-app",
        sizeBytes: 10_000,
        sha256: String(repeating: "b", count: 64),
        url: URL(
            string: "https://github.com/Lore-Hex/QuillCode/releases/download/\(tag)/" +
                "Quill-Cowork-macOS-arm64.zip"
        )!
    )
    return QuillCodeDesktopUpdateManifest(
        schemaVersion: 1,
        product: "Quill Cowork",
        channel: configuration.channel,
        tag: tag,
        releaseURL: URL(
            string: "https://github.com/Lore-Hex/QuillCode/releases/tag/\(tag)"
        )!,
        commit: String(repeating: "a", count: 40),
        version: "0.2.0",
        build: "43",
        generatedAt: "2026-08-08T00:00:00Z",
        workflowRunURL: URL(
            string: "https://github.com/Lore-Hex/QuillCode/actions/runs/1"
        )!,
        updater: .init(
            schemaVersion: 1,
            format: "github-release-manifest",
            channel: configuration.channel,
            manifestURL: configuration.manifestURL,
            stableManifestURL: configuration.stableManifestURL,
            testerManifestURL: configuration.testerManifestURL,
            bundleIdentifier: configuration.bundleIdentifier,
            minimumSystemVersion: "14.0",
            codesign: codesign,
            signingTeamIdentifier: signingTeamIdentifier,
            notarized: notarized,
            macOSAppAsset: asset
        ),
        assets: [asset]
    )
}
