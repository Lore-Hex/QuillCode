import Foundation

enum ToolArtifactPipfileLockPreviewBuilder {
    static func pipfileLockPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactPipfileLockPreview? {
        guard kind == .file,
              let fileURL = localArtifactFileURL(for: value),
              fileURL.lastPathComponent.lowercased() == "pipfile.lock"
        else {
            return nil
        }

        do {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard resourceValues.isRegularFile == true else { return nil }
            let fileSize = max(resourceValues.fileSize ?? 0, 0)
            guard fileSize > 0, fileSize <= byteLimit else { return nil }
            let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            guard !data.contains(0) else { return nil }
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            guard let root = json as? [String: Any],
                  root["_meta"] is [String: Any],
                  let preview = preview(
                    from: root,
                    byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
                  )
            else {
                return nil
            }
            return preview.hasDisplayContent ? preview : nil
        } catch {
            return nil
        }
    }

    private static func preview(
        from root: [String: Any],
        byteSizeLabel: String?
    ) -> ToolArtifactPipfileLockPreview? {
        let defaultPackages = packageRecords(from: root["default"], dependencySet: .default)
        let developPackages = packageRecords(from: root["develop"], dependencySet: .develop)
        let packages = (defaultPackages + developPackages).sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        guard !packages.isEmpty else { return nil }
        let sourceLabels = sourcePreviewLabels(from: root, packages: packages)
        return ToolArtifactPipfileLockPreview(
            packageCount: packages.count,
            defaultPackageCount: defaultPackages.count,
            developPackageCount: developPackages.count,
            pinnedPackageCount: packages.filter(\.isPinned).count,
            editablePackageCount: packages.filter(\.isEditable).count,
            hashCount: packages.reduce(0) { $0 + $1.hashCount },
            sourceCount: sourceLabels.count,
            sourcePreviewLabels: sourceLabels,
            packagePreviewLabels: Array(packages.prefix(previewLabelLimit)).map(\.label),
            byteSizeLabel: byteSizeLabel
        )
    }

    private static func packageRecords(from value: Any?, dependencySet: DependencySet) -> [PackageRecord] {
        guard let packages = value as? [String: Any] else { return [] }
        return packages.compactMap { name, value in
            guard let attributes = value as? [String: Any] else {
                return PackageRecord(name: sanitizedLabel(name), dependencySet: dependencySet)
            }
            let version = stringValue(attributes["version"])
            return PackageRecord(
                name: sanitizedLabel(name),
                version: sanitizedVersion(version),
                dependencySet: dependencySet,
                isPinned: version.map(isPinnedVersion) ?? false,
                isEditable: boolValue(attributes["editable"]) == true,
                hashCount: arrayCount(attributes["hashes"]),
                sourceLabel: firstSourceLabel(in: attributes)
            )
        }
    }

    private static func sourcePreviewLabels(from root: [String: Any], packages: [PackageRecord]) -> [String] {
        var labels: [String] = []
        var seen = Set<String>()

        func append(_ label: String?) {
            guard labels.count < previewLabelLimit,
                  let label,
                  !label.isEmpty,
                  !seen.contains(label)
            else {
                return
            }
            seen.insert(label)
            labels.append(label)
        }

        if let meta = root["_meta"] as? [String: Any],
           let sources = meta["sources"] as? [[String: Any]] {
            for source in sources {
                append(stringValue(source["url"]).flatMap(hostLabel))
            }
        }
        for package in packages {
            append(package.sourceLabel)
        }
        return labels
    }

    private static func firstSourceLabel(in attributes: [String: Any]) -> String? {
        for key in ["file", "git", "ref"] {
            if let label = stringValue(attributes[key]).flatMap(hostLabel) {
                return label
            }
        }
        return nil
    }

    private static func hostLabel(from value: String) -> String? {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("git+") {
            text.removeFirst(4)
        }
        guard let url = URL(string: text),
              let host = url.host?.lowercased()
        else {
            return nil
        }
        return sanitizedLabel(host)
    }

    private static func sanitizedVersion(_ value: String?) -> String? {
        guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        while value.hasPrefix("=") {
            value.removeFirst()
        }
        return sanitizedLabel(value)
    }

    private static func isPinnedVersion(_ value: String) -> Bool {
        value.hasPrefix("==") || value.hasPrefix("===")
    }

    private static func stringValue(_ value: Any?) -> String? {
        value as? String
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        value as? Bool
    }

    private static func arrayCount(_ value: Any?) -> Int {
        (value as? [Any])?.count ?? 0
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
        var dependencySet: DependencySet
        var isPinned = false
        var isEditable = false
        var hashCount = 0
        var sourceLabel: String?

        var label: String {
            ToolArtifactPipfileLockPreviewBuilder.sanitizedLabel(version.map { "\(name)==\($0)" } ?? name)
        }
    }

    private enum DependencySet {
        case `default`
        case develop
    }

    private static let byteLimit = 512 * 1_024
    private static let previewLabelLimit = 6
    private static let characterLimit = 120
}
