import Foundation
import QuillCodeApp

enum QuillCodeDesktopUpdateManifestValidator {
    static let maximumAssetBytes: Int64 = 2 * 1_024 * 1_024 * 1_024

    static func validate(
        _ manifest: QuillCodeDesktopUpdateManifest,
        configuration: QuillCodeDesktopUpdateConfiguration
    ) throws -> QuillCodeDesktopUpdateCheckResult {
        guard manifest.schemaVersion == 1,
              manifest.updater.schemaVersion == 1,
              manifest.updater.format == "github-release-manifest"
        else {
            throw QuillCodeDesktopUpdateError.unsupportedManifest
        }
        guard manifest.product == QuillCodeProduct.displayName,
              manifest.channel == configuration.channel,
              manifest.updater.channel == configuration.channel,
              manifest.updater.bundleIdentifier == configuration.bundleIdentifier
        else {
            throw QuillCodeDesktopUpdateError.wrongProductOrChannel
        }
        try validateSigning(manifest.updater, configuration: configuration)
        guard manifest.updater.manifestURL == configuration.manifestURL,
              manifest.updater.stableManifestURL == configuration.stableManifestURL,
              manifest.updater.testerManifestURL == configuration.testerManifestURL
        else {
            throw QuillCodeDesktopUpdateError.unexpectedFeed
        }
        guard isHex(manifest.commit, length: 40),
              let releaseVersion = QuillCodeDesktopSemanticVersion(manifest.version),
              let releaseBuild = UInt64(manifest.build),
              let currentVersion = QuillCodeDesktopSemanticVersion(configuration.currentVersion),
              let currentBuild = UInt64(configuration.currentBuild),
              QuillCodeDesktopSemanticVersion(manifest.updater.minimumSystemVersion) != nil
        else {
            throw QuillCodeDesktopUpdateError.invalidVersionMetadata
        }

        let repositoryScope = try repositoryScope(for: configuration)
        guard repositoryScope.containsReleasePage(manifest.releaseURL, tag: manifest.tag),
              repositoryScope.containsManifestURL(manifest.updater.manifestURL),
              repositoryScope.containsManifestURL(manifest.updater.stableManifestURL),
              repositoryScope.containsManifestURL(manifest.updater.testerManifestURL)
        else {
            throw QuillCodeDesktopUpdateError.unexpectedFeed
        }
        let asset = try compatibleAsset(in: manifest, configuration: configuration, scope: repositoryScope)
        guard releaseVersion > currentVersion || (
            releaseVersion == currentVersion && releaseBuild > currentBuild
        ) else {
            return .upToDate(latestVersion: manifest.version, latestBuild: manifest.build)
        }
        return .updateAvailable(QuillCodeDesktopUpdateRelease(
            channel: manifest.channel,
            tag: manifest.tag,
            releaseURL: manifest.releaseURL,
            commit: manifest.commit,
            version: manifest.version,
            build: manifest.build,
            asset: asset
        ))
    }

    private static func validateSigning(
        _ updater: QuillCodeDesktopUpdateManifest.Updater,
        configuration: QuillCodeDesktopUpdateConfiguration
    ) throws {
        if let expectedTeam = configuration.expectedSigningTeamIdentifier {
            guard updater.codesign == "developer-id",
                  updater.signingTeamIdentifier == expectedTeam
            else {
                throw QuillCodeDesktopUpdateError.wrongSigningIdentity
            }
        }
        if configuration.channel == .stable {
            guard configuration.expectedSigningTeamIdentifier != nil,
                  updater.notarized == true
            else {
                throw QuillCodeDesktopUpdateError.unsignedStableUpdate
            }
        }
    }

    private static func compatibleAsset(
        in manifest: QuillCodeDesktopUpdateManifest,
        configuration: QuillCodeDesktopUpdateConfiguration,
        scope: GitHubReleaseRepositoryScope
    ) throws -> QuillCodeDesktopUpdateManifest.Asset {
        guard let updaterAsset = manifest.updater.macOSAppAsset,
              let asset = manifest.assets.first(where: { $0.name == updaterAsset.name }),
              asset == updaterAsset,
              asset.kind == "app",
              asset.platform == "macOS",
              asset.arch == configuration.architecture,
              asset.install == "zip-app",
              asset.sizeBytes > 0,
              asset.sizeBytes <= maximumAssetBytes,
              isSafeAssetName(asset.name),
              isHex(asset.sha256, length: 64),
              scope.containsDownloadURL(asset.url, tag: manifest.tag)
        else {
            throw QuillCodeDesktopUpdateError.noCompatibleApplication
        }
        return asset
    }

    private static func repositoryScope(
        for configuration: QuillCodeDesktopUpdateConfiguration
    ) throws -> GitHubReleaseRepositoryScope {
        guard let scope = GitHubReleaseRepositoryScope(manifestURL: configuration.manifestURL),
              scope == GitHubReleaseRepositoryScope(manifestURL: configuration.stableManifestURL),
              scope == GitHubReleaseRepositoryScope(manifestURL: configuration.testerManifestURL)
        else {
            throw QuillCodeDesktopUpdateError.unexpectedFeed
        }
        return scope
    }

    private static func isSafeAssetName(_ name: String) -> Bool {
        !name.isEmpty &&
            name.count <= 180 &&
            name == (name as NSString).lastPathComponent &&
            !name.contains("..")
    }

    private static func isHex(_ value: String, length: Int) -> Bool {
        value.count == length && value.unicodeScalars.allSatisfy { scalar in
            ("0"..."9").contains(Character(scalar)) || ("a"..."f").contains(Character(scalar))
        }
    }
}

struct GitHubReleaseRepositoryScope: Equatable, Sendable {
    private var owner: String
    private var repository: String

    init?(manifestURL: URL) {
        guard manifestURL.scheme?.lowercased() == "https",
              manifestURL.host?.lowercased() == "github.com"
        else {
            return nil
        }
        let components = manifestURL.pathComponents.filter { $0 != "/" }
        guard components.count >= 4,
              components[2] == "releases",
              !components[0].isEmpty,
              !components[1].isEmpty
        else {
            return nil
        }
        owner = components[0]
        repository = components[1]
    }

    func containsManifestURL(_ url: URL) -> Bool {
        containsRepositoryURL(url) && url.pathExtension == "json"
    }

    func containsDownloadURL(_ url: URL, tag: String) -> Bool {
        guard containsRepositoryURL(url) else { return false }
        let components = url.pathComponents.filter { $0 != "/" }
        return components.count >= 6 &&
            components[2] == "releases" &&
            components[3] == "download" &&
            components[4] == tag
    }

    func containsReleasePage(_ url: URL, tag: String) -> Bool {
        guard containsRepositoryURL(url) else { return false }
        let components = url.pathComponents.filter { $0 != "/" }
        return components.count == 5 &&
            components[2] == "releases" &&
            components[3] == "tag" &&
            components[4] == tag
    }

    private func containsRepositoryURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "github.com"
        else {
            return false
        }
        let components = url.pathComponents.filter { $0 != "/" }
        return components.count >= 2 && components[0] == owner && components[1] == repository
    }
}
