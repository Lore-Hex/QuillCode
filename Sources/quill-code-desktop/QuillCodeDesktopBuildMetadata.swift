import Foundation

struct QuillCodeDesktopBuildMetadata: Equatable, Sendable {
    static let commitInfoKey = "QuillCodeBuildCommit"

    var version: String
    var build: String
    var commit: String
    var channel: String
    var architecture: String
    var operatingSystem: String

    static func current(
        configuration: QuillCodeDesktopUpdateConfiguration?,
        bundle: Bundle = .main,
        architecture: String = QuillCodeDesktopArchitecture.current,
        operatingSystemVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    ) -> Self {
        let version = configuration?.currentVersion
            ?? infoString("CFBundleShortVersionString", bundle: bundle)
            ?? "development"
        let build = configuration?.currentBuild
            ?? infoString("CFBundleVersion", bundle: bundle)
            ?? "development"
        let rawCommit = infoString(commitInfoKey, bundle: bundle) ?? "development"
        let commit = isCanonicalCommit(rawCommit) ? rawCommit : "development"
        let channel = configuration?.channel.rawValue
            ?? infoString(QuillCodeDesktopUpdateConfiguration.channelInfoKey, bundle: bundle)
            ?? "development"
        let resolvedArchitecture = configuration?.architecture ?? architecture
        let system = [
            operatingSystemVersion.majorVersion,
            operatingSystemVersion.minorVersion,
            operatingSystemVersion.patchVersion
        ].map(String.init).joined(separator: ".")
        return Self(
            version: version,
            build: build,
            commit: commit,
            channel: channel,
            architecture: resolvedArchitecture,
            operatingSystem: "macOS \(system)"
        )
    }

    static func isCanonicalCommit(_ value: String) -> Bool {
        value.count == 40 && value.unicodeScalars.allSatisfy { scalar in
            ("0"..."9").contains(Character(scalar)) || ("a"..."f").contains(Character(scalar))
        }
    }

    private static func infoString(_ key: String, bundle: Bundle) -> String? {
        guard let value = bundle.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
