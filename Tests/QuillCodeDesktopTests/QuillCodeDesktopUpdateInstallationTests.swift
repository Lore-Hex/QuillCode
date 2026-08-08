import XCTest
@testable import quill_code_desktop

final class QuillCodeDesktopUpdateInstallationTests: XCTestCase {
    func testReleaseFallsBackToReleasePageWithoutInstallerMetadata() {
        let release = makeRelease()

        XCTAssertNil(release.installerAsset)
        XCTAssertEqual(release.manualInstallationURL, release.releaseURL)
    }

    func testValidatorCarriesOnlyATrustedArchitectureMatchingInstaller() throws {
        let configuration = makeConfiguration()
        let installer = makeManualInstallerAsset()
        let result = try QuillCodeDesktopUpdateManifestValidator.validate(
            installationManifest(configuration: configuration, installers: [installer]),
            configuration: configuration
        )
        guard case .updateAvailable(let release) = result else {
            return XCTFail("Expected an available update")
        }
        XCTAssertEqual(release.installerAsset, installer)
        XCTAssertEqual(release.manualInstallationURL, installer.url)

        var otherArchitecture = installer
        otherArchitecture.arch = "x86_64"
        let otherResult = try QuillCodeDesktopUpdateManifestValidator.validate(
            installationManifest(configuration: configuration, installers: [otherArchitecture]),
            configuration: configuration
        )
        guard case .updateAvailable(let releaseWithoutInstaller) = otherResult else {
            return XCTFail("Expected an available app update")
        }
        XCTAssertNil(releaseWithoutInstaller.installerAsset)
    }

    func testValidatorRejectsHostileMalformedAndDuplicateInstallers() {
        let configuration = makeConfiguration()
        var hostile = makeManualInstallerAsset()
        hostile.url = URL(
            string: "https://github.com/Elsewhere/Other/releases/download/tester-latest/Quill-Cowork.dmg"
        )!
        var mismatchedName = makeManualInstallerAsset()
        mismatchedName.url = mismatchedName.url.deletingLastPathComponent()
            .appendingPathComponent("another-installer.dmg")
        var wrongExtension = makeManualInstallerAsset()
        wrongExtension.name = "Quill-Cowork-macOS-arm64.zip"
        wrongExtension.url = wrongExtension.url.deletingLastPathComponent()
            .appendingPathComponent(wrongExtension.name)
        var queryURL = makeManualInstallerAsset()
        queryURL.url = URL(string: queryURL.url.absoluteString + "?download=1")!
        var invalidDigest = makeManualInstallerAsset()
        invalidDigest.sha256 = "not-a-digest"
        let manifests = [
            installationManifest(configuration: configuration, installers: [hostile]),
            installationManifest(configuration: configuration, installers: [mismatchedName]),
            installationManifest(configuration: configuration, installers: [wrongExtension]),
            installationManifest(configuration: configuration, installers: [queryURL]),
            installationManifest(configuration: configuration, installers: [invalidDigest]),
            installationManifest(
                configuration: configuration,
                installers: [makeManualInstallerAsset(), makeManualInstallerAsset()]
            ),
        ]

        for manifest in manifests {
            XCTAssertThrowsError(
                try QuillCodeDesktopUpdateManifestValidator.validate(
                    manifest,
                    configuration: configuration
                )
            ) { error in
                XCTAssertEqual(error as? QuillCodeDesktopUpdateError, .noCompatibleApplication)
            }
        }
    }

    func testInspectorDetectsWritableReadOnlyAndIncompleteLocations() throws {
        let root = try temporaryDirectory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }
        let applicationURL = root.appendingPathComponent("Quill Cowork.app", isDirectory: true)
        let executableURL = applicationURL.appendingPathComponent(
            "Contents/MacOS/Quill Cowork",
            isDirectory: false
        )
        try FileManager.default.createDirectory(
            at: executableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executableURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executableURL.path)
        var configuration = makeConfiguration()
        configuration.applicationURL = applicationURL
        let inspector = QuillCodeDesktopUpdateInstallationInspector(
            runningExecutableURL: executableURL
        )

        XCTAssertEqual(inspector.availability(for: configuration), .available)

        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
        XCTAssertEqual(inspector.availability(for: configuration), .requiresRelocation)

        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        let outsideExecutableURL = root.appendingPathComponent("outside-executable", isDirectory: false)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: outsideExecutableURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: outsideExecutableURL.path
        )
        XCTAssertEqual(
            QuillCodeDesktopUpdateInstallationInspector(runningExecutableURL: outsideExecutableURL)
                .availability(for: configuration),
            .requiresRelocation
        )

        configuration.applicationURL = root.appendingPathComponent("Missing.app", isDirectory: true)
        XCTAssertEqual(inspector.availability(for: configuration), .requiresRelocation)
        XCTAssertEqual(
            QuillCodeDesktopUpdateInstallationInspector(runningExecutableURL: nil)
                .availability(for: configuration),
            .requiresRelocation
        )

        let regularFileURL = root.appendingPathComponent("NotADirectory.app", isDirectory: false)
        try Data().write(to: regularFileURL)
        configuration.applicationURL = regularFileURL
        XCTAssertEqual(inspector.availability(for: configuration), .requiresRelocation)
    }
}

func makeManualInstallerAsset() -> QuillCodeDesktopUpdateManifest.Asset {
    QuillCodeDesktopUpdateManifest.Asset(
        name: "Quill-Cowork-macOS-arm64.dmg",
        kind: "installer",
        platform: "macOS",
        arch: "arm64",
        install: "dmg-app",
        sizeBytes: 12_000,
        sha256: String(repeating: "c", count: 64),
        url: URL(
            string: "https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/Quill-Cowork-macOS-arm64.dmg"
        )!
    )
}

private func installationManifest(
    configuration: QuillCodeDesktopUpdateConfiguration,
    installers: [QuillCodeDesktopUpdateManifest.Asset]
) -> QuillCodeDesktopUpdateManifest {
    let app = QuillCodeDesktopUpdateManifest.Asset(
        name: "Quill-Cowork-macOS-arm64.zip",
        kind: "app",
        platform: "macOS",
        arch: "arm64",
        install: "zip-app",
        sizeBytes: 10_000,
        sha256: String(repeating: "b", count: 64),
        url: URL(
            string: "https://github.com/Lore-Hex/QuillCode/releases/download/tester-latest/Quill-Cowork-macOS-arm64.zip"
        )!
    )
    return QuillCodeDesktopUpdateManifest(
        schemaVersion: 1,
        product: "Quill Cowork",
        channel: .tester,
        tag: "tester-latest",
        releaseURL: URL(string: "https://github.com/Lore-Hex/QuillCode/releases/tag/tester-latest")!,
        commit: String(repeating: "a", count: 40),
        version: "0.1.0",
        build: "43",
        generatedAt: "2026-08-08T00:00:00Z",
        workflowRunURL: URL(string: "https://github.com/Lore-Hex/QuillCode/actions/runs/1")!,
        updater: .init(
            schemaVersion: 1,
            format: "github-release-manifest",
            channel: .tester,
            manifestURL: configuration.manifestURL,
            stableManifestURL: configuration.stableManifestURL,
            testerManifestURL: configuration.testerManifestURL,
            bundleIdentifier: configuration.bundleIdentifier,
            minimumSystemVersion: "14.0",
            codesign: "ad-hoc",
            signingTeamIdentifier: nil,
            notarized: false,
            macOSAppAsset: app
        ),
        assets: [app] + installers
    )
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
        "QuillCodeUpdateInstallationTests-\(UUID().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    return url
}
