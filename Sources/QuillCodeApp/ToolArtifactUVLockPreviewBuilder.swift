import Foundation

enum ToolArtifactUVLockPreviewBuilder {
    static func uvLockPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactUVLockPreview? {
        guard kind == .file,
              let fileURL = localArtifactFileURL(for: value),
              fileURL.lastPathComponent.lowercased() == "uv.lock"
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
                rootPythonRequirement: rootPythonRequirement(from: text),
                byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
            )
            return preview.hasDisplayContent ? preview : nil
        } catch {
            return nil
        }
    }

    private static func preview(
        from packages: [PackageRecord],
        rootPythonRequirement: String?,
        byteSizeLabel: String?
    ) -> ToolArtifactUVLockPreview {
        let sourceLabels = sourcePreviewLabels(from: packages)
        return ToolArtifactUVLockPreview(
            pythonRequirement: rootPythonRequirement,
            packageCount: packages.count,
            versionedPackageCount: packages.filter { $0.version != nil }.count,
            dependencyCount: packages.reduce(0) { $0 + $1.dependencyCount },
            sourceCount: sourceLabels.count,
            hashCount: packages.reduce(0) { $0 + $1.hashCount },
            sourcePreviewLabels: sourceLabels,
            packagePreviewLabels: Array(packages.prefix(previewLabelLimit)).map(\.label),
            byteSizeLabel: byteSizeLabel
        )
    }

    private static func packageRecords(from text: String) -> [PackageRecord] {
        var packages: [PackageRecord] = []
        var current = PartialPackage()
        var insidePackage = false
        var insideDependencyList = false

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
                insideDependencyList = false
                continue
            }
            if line.hasPrefix("[") {
                insideDependencyList = false
                continue
            }
            guard insidePackage else {
                continue
            }
            current.addHashCount(from: line)
            if insideDependencyList {
                current.addDependencyNameReferences(from: line)
                if line.contains("]") {
                    insideDependencyList = false
                }
            } else if line.hasPrefix("dependencies") {
                current.addDependencyCount(from: line)
                insideDependencyList = line.contains("[") && !line.contains("]")
            }
            current.addSourceLabel(from: line)
            guard let assignment = assignment(from: line) else { continue }
            current.set(value: assignment.value, for: assignment.key)
        }
        flushCurrentPackage()

        return packages.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func rootPythonRequirement(from text: String) -> String? {
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            guard let assignment = assignment(from: line),
                  assignment.key == "requires-python"
            else {
                continue
            }
            return unquoted(assignment.value)
        }
        return nil
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
            for label in package.sourceLabels where labels.count < previewLabelLimit && !seen.contains(label) {
                seen.insert(label)
                labels.append(label)
            }
        }
        return labels
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

    private static func unquoted(_ value: String) -> String {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("\""), text.hasSuffix("\""), text.count >= 2 {
            text.removeFirst()
            text.removeLast()
        }
        return sanitizedLabel(text)
    }

    private static func dependencyCount(in value: String) -> Int {
        let quotedNames = (try? NSRegularExpression(pattern: #"name\s*=\s*"[^"]+""#))
            .map { regex in
                regex.numberOfMatches(
                    in: value,
                    range: NSRange(value.startIndex..., in: value)
                )
            } ?? 0
        if quotedNames > 0 {
            return quotedNames
        }
        return value.components(separatedBy: "{").count - 1
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
        var sourceLabels: [String] = []
        var dependencyCount = 0
        var hashCount = 0

        mutating func set(value: String, for key: String) {
            switch key {
            case "name":
                name = ToolArtifactUVLockPreviewBuilder.unquoted(value)
            case "version":
                version = ToolArtifactUVLockPreviewBuilder.unquoted(value)
            case "source", "sdist", "wheels":
                addSourceLabel(from: value)
            case "dependencies":
                break
            default:
                break
            }
        }

        mutating func addSourceLabel(from line: String) {
            for label in ToolArtifactUVLockPreviewBuilder.hosts(in: line) where !sourceLabels.contains(label) {
                sourceLabels.append(label)
            }
        }

        mutating func addDependencyCount(from line: String) {
            guard line.hasPrefix("dependencies") else { return }
            dependencyCount += ToolArtifactUVLockPreviewBuilder.dependencyCount(in: line)
        }

        mutating func addDependencyNameReferences(from line: String) {
            dependencyCount += ToolArtifactUVLockPreviewBuilder.dependencyCount(in: line)
        }

        mutating func addHashCount(from line: String) {
            hashCount += ToolArtifactUVLockPreviewBuilder.hashCount(in: line)
        }

        var packageRecord: PackageRecord? {
            guard let name, !name.isEmpty else { return nil }
            return PackageRecord(
                name: name,
                version: version,
                sourceLabels: sourceLabels,
                dependencyCount: dependencyCount,
                hashCount: hashCount
            )
        }
    }

    private struct PackageRecord {
        var name: String
        var version: String?
        var sourceLabels: [String]
        var dependencyCount: Int
        var hashCount: Int

        var label: String {
            ToolArtifactUVLockPreviewBuilder.sanitizedLabel(version.map { "\(name)@\($0)" } ?? name)
        }
    }

    private static let trackedKeys: Set<String> = [
        "name",
        "version",
        "requires-python",
        "source",
        "dependencies",
        "sdist",
        "wheels"
    ]
    private static let byteLimit = 512 * 1_024
    private static let previewLabelLimit = 6
    private static let characterLimit = 120
}
