import Foundation

enum ToolArtifactNPMLockfilePreviewBuilder {
    static func npmLockfilePreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactNPMLockfilePreview? {
        guard kind == .file,
              let fileURL = localArtifactFileURL(for: value),
              fileURL.lastPathComponent.lowercased() == "package-lock.json"
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
                  isNPMLockfile(root)
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

    private static func isNPMLockfile(_ root: [String: Any]) -> Bool {
        guard root["lockfileVersion"] != nil else { return false }
        return root["packages"] is [String: Any] || root["dependencies"] is [String: Any]
    }

    private static func preview(from root: [String: Any], byteSizeLabel: String?) -> ToolArtifactNPMLockfilePreview {
        let packages = root["packages"] as? [String: Any] ?? [:]
        let packageEntries = packageRecords(from: packages)
        let dependencyEntries = root["dependencies"] as? [String: Any] ?? [:]
        let dependencyCount = max(dependencyEntries.count, packageEntries.count)

        return ToolArtifactNPMLockfilePreview(
            lockfileVersion: lockfileVersionLabel(root["lockfileVersion"]),
            rootPackageLabel: rootPackageLabel(from: root, packages: packages),
            packageCount: packageEntries.count,
            dependencyCount: dependencyCount,
            devPackageCount: packageEntries.filter(\.isDev).count,
            optionalPackageCount: packageEntries.filter(\.isOptional).count,
            resolvedHostLabels: resolvedHostLabels(from: packageEntries),
            packagePreviewLabels: packagePreviewLabels(from: packageEntries, dependencyEntries: dependencyEntries),
            byteSizeLabel: byteSizeLabel
        )
    }

    private static func packageRecords(from packages: [String: Any]) -> [PackageRecord] {
        packages.compactMap { path, value in
            guard !path.isEmpty,
                  let object = value as? [String: Any]
            else {
                return nil
            }
            return PackageRecord(
                path: path,
                version: stringValue(object["version"]),
                resolved: stringValue(object["resolved"]),
                isDev: boolValue(object["dev"]),
                isOptional: boolValue(object["optional"])
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func rootPackageLabel(from root: [String: Any], packages: [String: Any]) -> String? {
        let rootPackage = packages[""] as? [String: Any]
        let name = stringValue(rootPackage?["name"]) ?? stringValue(root["name"])
        let version = stringValue(rootPackage?["version"]) ?? stringValue(root["version"])
        guard let name else { return nil }
        return version.map { sanitizedLabel("\(name)@\($0)") } ?? sanitizedLabel(name)
    }

    private static func packagePreviewLabels(
        from packageEntries: [PackageRecord],
        dependencyEntries: [String: Any]
    ) -> [String] {
        if !packageEntries.isEmpty {
            return Array(packageEntries.prefix(previewLabelLimit)).map(\.label)
        }
        let labels = dependencyEntries.keys
            .sorted()
            .prefix(previewLabelLimit)
            .map(sanitizedLabel)
        return Array(labels)
    }

    private static func resolvedHostLabels(from packageEntries: [PackageRecord]) -> [String] {
        var hosts: [String] = []
        var seen = Set<String>()
        for package in packageEntries {
            guard hosts.count < previewLabelLimit,
                  let resolved = package.resolved,
                  let host = URL(string: resolved)?.host?.lowercased(),
                  !seen.contains(host)
            else {
                continue
            }
            seen.insert(host)
            hosts.append(sanitizedLabel(host))
        }
        return hosts
    }

    private static func lockfileVersionLabel(_ value: Any?) -> String? {
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

    private static func boolValue(_ value: Any?) -> Bool {
        guard let bool = value as? Bool else { return false }
        return bool
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
        var path: String
        var version: String?
        var resolved: String?
        var isDev: Bool
        var isOptional: Bool

        var name: String {
            path
                .split(separator: "/")
                .suffix(2)
                .joined(separator: "/")
                .replacingOccurrences(of: "node_modules/", with: "")
        }

        var label: String {
            var label = version.map { "\(name)@\($0)" } ?? name
            var tags: [String] = []
            if isDev { tags.append("dev") }
            if isOptional { tags.append("optional") }
            if !tags.isEmpty {
                label += " · \(tags.joined(separator: ", "))"
            }
            return sanitizedLabel(label)
        }
    }

    private static let byteLimit = 512 * 1_024
    private static let previewLabelLimit = 6
    private static let characterLimit = 120
}
