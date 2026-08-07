import Foundation
import QuillCodeApp

enum QuillCodeDesktopUpdateChannel: String, Codable, Sendable {
    case stable
    case tester
}

struct QuillCodeDesktopUpdateConfiguration: Equatable, Sendable {
    static let manifestInfoKey = "QuillCodeUpdateManifestURL"
    static let channelInfoKey = "QuillCodeUpdateChannel"
    static let stableManifestInfoKey = "QuillCodeStableUpdateManifestURL"
    static let testerManifestInfoKey = "QuillCodeTesterUpdateManifestURL"
    static let signingTeamInfoKey = "QuillCodeSigningTeamIdentifier"

    var channel: QuillCodeDesktopUpdateChannel
    var manifestURL: URL
    var stableManifestURL: URL
    var testerManifestURL: URL
    var currentVersion: String
    var currentBuild: String
    var bundleIdentifier: String
    var architecture: String
    var applicationURL: URL
    var expectedSigningTeamIdentifier: String?

    static func bundled(
        bundle: Bundle = .main,
        architecture: String = QuillCodeDesktopArchitecture.current
    ) -> Self? {
        guard let channelValue = bundle.object(forInfoDictionaryKey: channelInfoKey) as? String,
              let channel = QuillCodeDesktopUpdateChannel(rawValue: channelValue),
              let manifestURL = infoURL(manifestInfoKey, bundle: bundle),
              let stableManifestURL = infoURL(stableManifestInfoKey, bundle: bundle),
              let testerManifestURL = infoURL(testerManifestInfoKey, bundle: bundle),
              let currentVersion = nonemptyInfoString("CFBundleShortVersionString", bundle: bundle),
              let currentBuild = nonemptyInfoString("CFBundleVersion", bundle: bundle),
              let bundleIdentifier = bundle.bundleIdentifier,
              bundleIdentifier == QuillCodeProduct.bundleIdentifier,
              QuillCodeDesktopSemanticVersion(currentVersion) != nil,
              UInt64(currentBuild) != nil,
              GitHubReleaseRepositoryScope(manifestURL: manifestURL) != nil,
              GitHubReleaseRepositoryScope(manifestURL: stableManifestURL) != nil,
              GitHubReleaseRepositoryScope(manifestURL: testerManifestURL) != nil
        else {
            return nil
        }
        return Self(
            channel: channel,
            manifestURL: manifestURL,
            stableManifestURL: stableManifestURL,
            testerManifestURL: testerManifestURL,
            currentVersion: currentVersion,
            currentBuild: currentBuild,
            bundleIdentifier: bundleIdentifier,
            architecture: architecture,
            applicationURL: bundle.bundleURL.standardizedFileURL,
            expectedSigningTeamIdentifier: nonemptyInfoString(signingTeamInfoKey, bundle: bundle)
        )
    }

    private static func infoURL(_ key: String, bundle: Bundle) -> URL? {
        guard let value = nonemptyInfoString(key, bundle: bundle),
              let url = URL(string: value),
              url.scheme?.lowercased() == "https"
        else {
            return nil
        }
        return url
    }

    private static func nonemptyInfoString(_ key: String, bundle: Bundle) -> String? {
        guard let value = bundle.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum QuillCodeDesktopArchitecture {
    static var current: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unknown"
        #endif
    }
}

struct QuillCodeDesktopUpdateManifest: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var product: String
    var channel: QuillCodeDesktopUpdateChannel
    var tag: String
    var releaseURL: URL
    var commit: String
    var version: String
    var build: String
    var generatedAt: String
    var workflowRunURL: URL
    var updater: Updater
    var assets: [Asset]

    struct Updater: Codable, Equatable, Sendable {
        var schemaVersion: Int
        var format: String
        var channel: QuillCodeDesktopUpdateChannel
        var manifestURL: URL
        var stableManifestURL: URL
        var testerManifestURL: URL
        var bundleIdentifier: String
        var minimumSystemVersion: String
        var codesign: String?
        var signingTeamIdentifier: String?
        var notarized: Bool?
        var macOSAppAsset: Asset?
    }

    struct Asset: Codable, Equatable, Sendable {
        var name: String
        var kind: String
        var platform: String
        var arch: String
        var install: String
        var sizeBytes: Int64
        var sha256: String
        var url: URL
    }
}

struct QuillCodeDesktopUpdateRelease: Equatable, Sendable {
    var channel: QuillCodeDesktopUpdateChannel
    var tag: String
    var releaseURL: URL
    var commit: String
    var version: String
    var build: String
    var asset: QuillCodeDesktopUpdateManifest.Asset

    var displayVersion: String {
        "\(version) (\(build))"
    }
}

enum QuillCodeDesktopUpdateCheckResult: Equatable, Sendable {
    case updateAvailable(QuillCodeDesktopUpdateRelease)
    case upToDate(latestVersion: String, latestBuild: String)
}

enum QuillCodeDesktopUpdateError: LocalizedError, Equatable, Sendable {
    case updatesUnavailable
    case invalidResponse
    case manifestTooLarge
    case unsupportedManifest
    case wrongProductOrChannel
    case unexpectedFeed
    case invalidVersionMetadata
    case noCompatibleApplication
    case wrongSigningIdentity
    case unsignedStableUpdate
    case downloadSizeMismatch
    case checksumMismatch
    case invalidApplication(String)
    case installationUnavailable
    case installationFailed(String)

    var errorDescription: String? {
        switch self {
        case .updatesUnavailable:
            "Updates are unavailable in this development build."
        case .invalidResponse:
            "The update server returned an invalid response."
        case .manifestTooLarge:
            "The update metadata exceeded its size limit."
        case .unsupportedManifest:
            "This build cannot read the update metadata format."
        case .wrongProductOrChannel:
            "The update does not match this app or release channel."
        case .unexpectedFeed:
            "The update metadata points outside the configured GitHub release feed."
        case .invalidVersionMetadata:
            "The update has invalid version metadata."
        case .noCompatibleApplication:
            "No compatible macOS app is available for this Mac."
        case .wrongSigningIdentity:
            "The update was not signed by Quill Cowork's configured distribution identity."
        case .unsignedStableUpdate:
            "The stable update is not marked as signed and notarized."
        case .downloadSizeMismatch:
            "The downloaded update size did not match the release metadata."
        case .checksumMismatch:
            "The downloaded update failed its SHA-256 integrity check."
        case .invalidApplication(let reason):
            "The downloaded app could not be verified: \(reason)"
        case .installationUnavailable:
            "Quill Cowork cannot replace itself from its current location."
        case .installationFailed(let reason):
            "The update could not be installed: \(reason)"
        }
    }
}
