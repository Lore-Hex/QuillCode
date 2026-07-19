import Foundation

enum ToolArtifactComposerLockfilePreviewBuilder {
    static func composerLockfilePreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactComposerLockfilePreview? {
        guard kind == .file,
              let fileURL = localArtifactFileURL(for: value),
              fileURL.lastPathComponent.lowercased() == "composer.lock"
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
                  isComposerLockfile(root)
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

    private static func isComposerLockfile(_ root: [String: Any]) -> Bool {
        root["packages"] is [[String: Any]]
            || root["packages-dev"] is [[String: Any]]
            || stringValue(root["plugin-api-version"]) != nil
            || stringValue(root["content-hash"]) != nil
    }

    private static func preview(from root: [String: Any], byteSizeLabel: String?) -> ToolArtifactComposerLockfilePreview {
        let packages = packageRecords(from: root["packages"])
        let devPackages = packageRecords(from: root["packages-dev"])
        let allPackages = (packages + devPackages).sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }

        return ToolArtifactComposerLockfilePreview(
            pluginAPIVersion: stringValue(root["plugin-api-version"]),
            contentHashPrefix: stringValue(root["content-hash"]).map(contentHashPrefix),
            packageCount: packages.count,
            devPackageCount: devPackages.count,
            resolvedHostLabels: resolvedHostLabels(from: allPackages),
            packagePreviewLabels: Array(allPackages.prefix(previewLabelLimit)).map(\.label),
            byteSizeLabel: byteSizeLabel
        )
    }

    private static func packageRecords(from value: Any?) -> [PackageRecord] {
        guard let objects = value as? [[String: Any]] else { return [] }
        return objects.compactMap { object in
            guard let name = stringValue(object["name"]) else { return nil }
            return PackageRecord(
                name: name,
                version: stringValue(object["version"]),
                sourceURL: stringValue((object["source"] as? [String: Any])?["url"]),
                distURL: stringValue((object["dist"] as? [String: Any])?["url"])
            )
        }
    }

    private static func resolvedHostLabels(from packages: [PackageRecord]) -> [String] {
        var labels: [String] = []
        var seen = Set<String>()
        for package in packages {
            guard labels.count < previewLabelLimit,
                  let host = package.resolvedHost,
                  !seen.contains(host)
            else {
                continue
            }
            seen.insert(host)
            labels.append(sanitizedLabel(host))
        }
        return labels
    }

    private static func contentHashPrefix(_ value: String) -> String {
        String(value.prefix(12))
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

    private struct PackageRecord {
        var name: String
        var version: String?
        var sourceURL: String?
        var distURL: String?

        var label: String {
            version.map { sanitizedLabel("\(name)@\($0)") } ?? name
        }

        var resolvedHost: String? {
            [distURL, sourceURL].compactMap { $0 }.lazy.compactMap { value in
                URL(string: value)?.host?.lowercased()
            }.first
        }
    }

    private static let byteLimit = 512 * 1_024
    private static let previewLabelLimit = 6
    private static let characterLimit = 120
}
