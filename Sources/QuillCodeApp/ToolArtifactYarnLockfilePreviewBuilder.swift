import Foundation

enum ToolArtifactYarnLockfilePreviewBuilder {
    static func yarnLockfilePreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactYarnLockfilePreview? {
        guard kind == .file,
              let fileURL = localArtifactFileURL(for: value),
              fileURL.lastPathComponent.lowercased() == "yarn.lock"
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
    ) -> ToolArtifactYarnLockfilePreview {
        ToolArtifactYarnLockfilePreview(
            packageCount: packages.count,
            versionedPackageCount: packages.filter { $0.version != nil }.count,
            resolvedPackageCount: packages.filter { $0.resolved != nil }.count,
            integrityCount: packages.filter { $0.integrity != nil }.count,
            resolvedHostLabels: resolvedHostLabels(from: packages),
            packagePreviewLabels: Array(packages.prefix(previewLabelLimit)).map(\.label),
            byteSizeLabel: byteSizeLabel
        )
    }

    private static func packageRecords(from text: String) -> [PackageRecord] {
        var packages: [PackageRecord] = []
        var current: PartialPackage?

        func flushCurrentPackage() {
            guard let package = current?.packageRecord else {
                current = nil
                return
            }
            packages.append(package)
            current = nil
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            if !line.hasPrefix(" "), trimmed.hasSuffix(":") {
                flushCurrentPackage()
                current = PartialPackage(descriptor: String(trimmed.dropLast()))
                continue
            }
            guard line.hasPrefix(" "),
                  let property = property(from: trimmed)
            else {
                continue
            }
            let (key, value) = property
            current?.set(value: unquoted(value), for: key)
        }
        flushCurrentPackage()

        return packages.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func property(from line: String) -> (key: String, value: String)? {
        for key in trackedKeys {
            if line.hasPrefix("\(key):") {
                let valueStart = line.index(line.startIndex, offsetBy: key.count + 1)
                let value = line[valueStart...].trimmingCharacters(in: .whitespaces)
                guard !value.isEmpty else { return nil }
                return (key, value)
            }
            if line.hasPrefix("\(key) ") {
                let valueStart = line.index(line.startIndex, offsetBy: key.count + 1)
                let value = line[valueStart...].trimmingCharacters(in: .whitespaces)
                guard !value.isEmpty else { return nil }
                return (key, value)
            }
        }
        return nil
    }

    private static func resolvedHostLabels(from packages: [PackageRecord]) -> [String] {
        var labels: [String] = []
        var seen = Set<String>()
        for package in packages {
            guard labels.count < previewLabelLimit,
                  let resolved = package.resolved,
                  let host = URL(string: resolved)?.host?.lowercased(),
                  !seen.contains(host)
            else {
                continue
            }
            seen.insert(host)
            labels.append(sanitizedLabel(host))
        }
        return labels
    }

    private static func packageName(from descriptor: String) -> String {
        let firstDescriptor = descriptor
            .split(separator: ",")
            .first
            .map(String.init) ?? descriptor
        var text = unquoted(firstDescriptor)
        if let npmRange = text.range(of: "@npm:") {
            text = String(text[..<npmRange.lowerBound])
        } else if let lastAt = text.lastIndex(of: "@"), lastAt != text.startIndex {
            text = String(text[..<lastAt])
        }
        return sanitizedLabel(text)
    }

    private static func unquoted(_ value: String) -> String {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("\""), text.hasSuffix("\""), text.count >= 2 {
            text.removeFirst()
            text.removeLast()
        }
        return sanitizedLabel(text)
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
        var descriptor: String
        var version: String?
        var resolved: String?
        var integrity: String?
        var checksum: String?

        mutating func set(value: String, for key: String) {
            switch key {
            case "version":
                version = value
            case "resolved", "resolution":
                resolved = value
            case "integrity":
                integrity = value
            case "checksum":
                checksum = value
            default:
                break
            }
        }

        var packageRecord: PackageRecord? {
            let name = ToolArtifactYarnLockfilePreviewBuilder.packageName(from: descriptor)
            guard !name.isEmpty, name != "__metadata" else { return nil }
            return PackageRecord(
                name: name,
                version: version,
                resolved: resolved,
                integrity: integrity ?? checksum
            )
        }
    }

    private struct PackageRecord {
        var name: String
        var version: String?
        var resolved: String?
        var integrity: String?

        var label: String {
            ToolArtifactYarnLockfilePreviewBuilder.sanitizedLabel(version.map { "\(name)@\($0)" } ?? name)
        }
    }

    private static let trackedKeys = ["version", "resolved", "resolution", "integrity", "checksum"]
    private static let byteLimit = 512 * 1_024
    private static let previewLabelLimit = 6
    private static let characterLimit = 120
}
