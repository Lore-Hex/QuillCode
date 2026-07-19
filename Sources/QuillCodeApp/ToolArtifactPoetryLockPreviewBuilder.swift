import Foundation

enum ToolArtifactPoetryLockPreviewBuilder {
    static func poetryLockPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactPoetryLockPreview? {
        guard kind == .file,
              let fileURL = localArtifactFileURL(for: value),
              fileURL.lastPathComponent.lowercased() == "poetry.lock"
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
                  let text = String(data: data, encoding: .utf8)
            else {
                return nil
            }
            let packages = packageRecords(from: text)
            guard !packages.isEmpty else { return nil }
            let preview = preview(
                from: packages,
                byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
            )
            return preview.hasDisplayContent ? preview : nil
        } catch {
            return nil
        }
    }

    private static func preview(
        from packages: [PackageRecord],
        byteSizeLabel: String?
    ) -> ToolArtifactPoetryLockPreview {
        ToolArtifactPoetryLockPreview(
            packageCount: packages.count,
            versionedPackageCount: packages.filter { $0.version != nil }.count,
            devPackageCount: packages.filter(\.isDevDependency).count,
            optionalPackageCount: packages.filter(\.isOptional).count,
            sourceCount: packages.filter { $0.sourceLabel != nil }.count,
            hashCount: packages.reduce(0) { $0 + $1.hashCount },
            sourcePreviewLabels: sourcePreviewLabels(from: packages),
            packagePreviewLabels: Array(packages.prefix(previewLabelLimit)).map(\.label),
            byteSizeLabel: byteSizeLabel
        )
    }

    private static func packageRecords(from text: String) -> [PackageRecord] {
        var packages: [PackageRecord] = []
        var current = PartialPackage()
        var insidePackage = false

        func flushCurrentPackage() {
            guard let package = current.packageRecord else {
                current = PartialPackage()
                return
            }
            packages.append(package)
            current = PartialPackage()
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            if line == "[[package]]" {
                if insidePackage {
                    flushCurrentPackage()
                }
                insidePackage = true
                continue
            }
            if line.hasPrefix("[") {
                continue
            }
            guard insidePackage else {
                continue
            }
            current.addHashCount(from: line)
            guard let assignment = assignment(from: line) else { continue }
            current.set(value: assignment.value, for: assignment.key)
        }
        flushCurrentPackage()

        return packages.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func assignment(from line: String) -> (key: String, value: String)? {
        guard let separator = line.firstIndex(of: "=") else { return nil }
        let key = line[..<separator].trimmingCharacters(in: .whitespaces)
        let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
        guard trackedKeys.contains(String(key)), !value.isEmpty else { return nil }
        return (String(key), String(value))
    }

    private static func sourcePreviewLabels(from packages: [PackageRecord]) -> [String] {
        var labels: [String] = []
        var seen = Set<String>()
        for package in packages {
            guard labels.count < previewLabelLimit,
                  let label = package.sourceLabel,
                  !seen.contains(label)
            else {
                continue
            }
            seen.insert(label)
            labels.append(label)
        }
        return labels
    }

    private static func sourceLabel(from value: String) -> String? {
        let hosts = hosts(in: value)
        if let host = hosts.first {
            return host
        }
        if let type = inlineTableValue(named: "type", in: value) {
            return sanitizedLabel(type)
        }
        return nil
    }

    private static func hosts(in value: String) -> [String] {
        value
            .split { $0.isWhitespace || $0 == "," || $0 == "}" || $0 == "]" }
            .compactMap { token in
                var text = String(token).trimmingCharacters(in: CharacterSet(charactersIn: "\\\",'()[]{}<>"))
                if text.lowercased().hasPrefix("git+") {
                    text.removeFirst(4)
                }
                guard text.hasPrefix("http://") || text.hasPrefix("https://"),
                      let host = URL(string: text)?.host?.lowercased()
                else {
                    return nil
                }
                return sanitizedLabel(host)
            }
    }

    private static func inlineTableValue(named key: String, in value: String) -> String? {
        guard let range = value.range(of: #"\b\#(NSRegularExpression.escapedPattern(for: key))\s*=\s*"([^"]+)""#, options: .regularExpression)
        else {
            return nil
        }
        let matched = String(value[range])
        guard let quote = matched.firstIndex(of: "\"") else { return nil }
        var content = String(matched[matched.index(after: quote)...])
        if content.hasSuffix("\"") {
            content.removeLast()
        }
        return sanitizedLabel(content)
    }

    private static func unquoted(_ value: String) -> String {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("\""), text.hasSuffix("\""), text.count >= 2 {
            text.removeFirst()
            text.removeLast()
        }
        return sanitizedLabel(text)
    }

    private static func boolValue(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true"
    }

    private static func containsDevGroup(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        return lowercased.contains("\"dev\"") || lowercased.contains("'dev'")
    }

    private static func hashCount(in value: String) -> Int {
        value.components(separatedBy: "hash =").count - 1
            + value.components(separatedBy: "\"hash\"").count - 1
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

    private struct PartialPackage {
        var name: String?
        var version: String?
        var category: String?
        var groups: String?
        var optional = false
        var sourceLabel: String?
        var hashCount = 0

        mutating func set(value: String, for key: String) {
            switch key {
            case "name":
                name = ToolArtifactPoetryLockPreviewBuilder.unquoted(value)
            case "version":
                version = ToolArtifactPoetryLockPreviewBuilder.unquoted(value)
            case "category":
                category = ToolArtifactPoetryLockPreviewBuilder.unquoted(value)
            case "groups":
                groups = value
            case "optional":
                optional = ToolArtifactPoetryLockPreviewBuilder.boolValue(value)
            case "source":
                sourceLabel = ToolArtifactPoetryLockPreviewBuilder.sourceLabel(from: value)
            default:
                break
            }
        }

        mutating func addHashCount(from line: String) {
            hashCount += ToolArtifactPoetryLockPreviewBuilder.hashCount(in: line)
        }

        var packageRecord: PackageRecord? {
            guard let name, !name.isEmpty else { return nil }
            return PackageRecord(
                name: name,
                version: version,
                isDevDependency: category == "dev" || groups.map(ToolArtifactPoetryLockPreviewBuilder.containsDevGroup) == true,
                isOptional: optional,
                sourceLabel: sourceLabel,
                hashCount: hashCount
            )
        }
    }

    private struct PackageRecord {
        var name: String
        var version: String?
        var isDevDependency: Bool
        var isOptional: Bool
        var sourceLabel: String?
        var hashCount: Int

        var label: String {
            ToolArtifactPoetryLockPreviewBuilder.sanitizedLabel(version.map { "\(name)@\($0)" } ?? name)
        }
    }

    private static let trackedKeys: Set<String> = [
        "name",
        "version",
        "category",
        "groups",
        "optional",
        "source",
        "files"
    ]
    private static let byteLimit = 512 * 1_024
    private static let previewLabelLimit = 6
    private static let characterLimit = 120
}
