import Foundation

enum ToolArtifactDenoLockPreviewBuilder {
    static func denoLockPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactDenoLockPreview? {
        guard kind == .file,
              let fileURL = localArtifactFileURL(for: value),
              fileURL.lastPathComponent.lowercased() == "deno.lock"
        else {
            return nil
        }

        do {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard resourceValues.isRegularFile == true else { return nil }
            let fileSize = max(resourceValues.fileSize ?? 0, 0)
            guard fileSize > 0, fileSize <= byteLimit else { return nil }
            let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            guard !data.contains(0),
                  let root = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                  isDenoLockfile(root)
            else {
                return nil
            }
            let preview = preview(
                from: root,
                byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
            )
            return preview.hasDisplayContent ? preview : nil
        } catch {
            return nil
        }
    }

    private static func isDenoLockfile(_ root: [String: Any]) -> Bool {
        root["version"] != nil
            && (root["remote"] is [String: Any]
                || root["npm"] is [String: Any]
                || root["jsr"] is [String: Any]
                || root["specifiers"] is [String: Any]
                || root["redirects"] is [String: Any])
    }

    private static func preview(from root: [String: Any], byteSizeLabel: String?) -> ToolArtifactDenoLockPreview {
        let remoteEntries = root["remote"] as? [String: Any] ?? [:]
        let redirects = root["redirects"] as? [String: Any] ?? [:]
        let npmSection = root["npm"] as? [String: Any] ?? [:]
        let npmPackages = npmPackageRecords(from: npmSection)
        let jsrPackages = packageRecords(from: root["jsr"])
        return ToolArtifactDenoLockPreview(
            lockfileVersion: versionLabel(root["version"]),
            remoteCount: remoteEntries.count,
            npmPackageCount: npmPackages.count,
            jsrPackageCount: jsrPackages.count,
            specifierCount: specifierCount(from: root, npmSection: npmSection),
            redirectCount: redirects.count,
            sourceHostLabels: sourceHostLabels(remoteEntries: remoteEntries, redirects: redirects),
            packagePreviewLabels: packagePreviewLabels(npmPackages: npmPackages, jsrPackages: jsrPackages),
            byteSizeLabel: byteSizeLabel
        )
    }

    private static func npmPackageRecords(from npmSection: [String: Any]) -> [PackageRecord] {
        if let packages = npmSection["packages"] as? [String: Any] {
            return packageRecords(from: packages, prefix: "npm:")
        }
        return npmSection
            .filter { key, _ in key != "specifiers" }
            .compactMap { key, value -> PackageRecord? in
                guard value is [String: Any] || value is String || value is NSNumber else { return nil }
                return PackageRecord(label: sanitizedLabel("npm:\(key)"))
            }
            .sorted()
    }

    private static func packageRecords(from value: Any?, prefix: String = "jsr:") -> [PackageRecord] {
        guard let packages = value as? [String: Any] else { return [] }
        return packages.keys
            .sorted()
            .map { PackageRecord(label: sanitizedLabel("\(prefix)\($0)")) }
    }

    private static func specifierCount(from root: [String: Any], npmSection: [String: Any]) -> Int {
        let topLevel = (root["specifiers"] as? [String: Any])?.count ?? 0
        let npm = (npmSection["specifiers"] as? [String: Any])?.count ?? 0
        return topLevel + npm
    }

    private static func sourceHostLabels(remoteEntries: [String: Any], redirects: [String: Any]) -> [String] {
        var labels: [String] = []
        var seen = Set<String>()
        let sourceValues = (Array(remoteEntries.keys) + Array(redirects.keys) + redirects.values.compactMap(stringValue))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        for value in sourceValues {
            guard let host = URL(string: value)?.host?.lowercased(),
                  seen.insert(host).inserted
            else {
                continue
            }
            if labels.count < previewLabelLimit {
                labels.append(sanitizedLabel(host))
            }
        }
        return labels
    }

    private static func packagePreviewLabels(npmPackages: [PackageRecord], jsrPackages: [PackageRecord]) -> [String] {
        Array((jsrPackages + npmPackages).sorted().prefix(previewLabelLimit)).map(\.label)
    }

    private static func versionLabel(_ value: Any?) -> String? {
        if let string = stringValue(value) {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let label = sanitizedLabel(string)
        return label.isEmpty ? nil : label
    }

    private static func sanitizedLabel(_ value: String) -> String {
        let collapsedWhitespace = value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(collapsedWhitespace.prefix(characterLimit))
    }

    private static func localArtifactFileURL(for value: String) -> URL? {
        if value.hasPrefix("/") {
            return URL(fileURLWithPath: value)
        }
        guard let url = URL(string: value),
              url.scheme?.lowercased() == "file"
        else {
            return nil
        }
        return url
    }

    private struct PackageRecord: Comparable {
        var label: String

        static func < (lhs: PackageRecord, rhs: PackageRecord) -> Bool {
            lhs.label.localizedStandardCompare(rhs.label) == .orderedAscending
        }
    }

    private static let byteLimit = 512 * 1_024
    private static let previewLabelLimit = 6
    private static let characterLimit = 120
}
