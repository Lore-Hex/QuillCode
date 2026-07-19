import Foundation

enum ToolArtifactCargoLockPreviewBuilder {
    static func cargoLockPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactCargoLockPreview? {
        guard kind == .file,
              let fileURL = localArtifactFileURL(for: value),
              fileURL.lastPathComponent.lowercased() == "cargo.lock"
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
    ) -> ToolArtifactCargoLockPreview {
        let sourceLabels = sourcePreviewLabels(from: packages)
        return ToolArtifactCargoLockPreview(
            packageCount: packages.count,
            versionedPackageCount: packages.filter { $0.version != nil }.count,
            sourceCount: packages.filter { $0.source != nil }.count,
            checksumCount: packages.filter { $0.checksum != nil }.count,
            sourcePreviewLabels: sourceLabels,
            packagePreviewLabels: Array(packages.prefix(previewLabelLimit)).map(\.label),
            byteSizeLabel: byteSizeLabel
        )
    }

    private static func packageRecords(from text: String) -> [PackageRecord] {
        var packages: [PackageRecord] = []
        var current: [String: String] = [:]

        func flushCurrentPackage() {
            guard let package = PackageRecord(fields: current) else {
                current.removeAll(keepingCapacity: true)
                return
            }
            packages.append(package)
            current.removeAll(keepingCapacity: true)
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line == "[[package]]" {
                flushCurrentPackage()
                continue
            }
            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            guard trackedKeys.contains(String(key)) else { continue }
            current[String(key)] = unquoted(value)
        }
        flushCurrentPackage()

        return packages.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func sourcePreviewLabels(from packages: [PackageRecord]) -> [String] {
        var labels: [String] = []
        var seen = Set<String>()
        for package in packages {
            guard labels.count < previewLabelLimit,
                  let source = package.source
            else {
                continue
            }
            let label = sourceLabel(from: source)
            guard !seen.contains(label) else { continue }
            seen.insert(label)
            labels.append(label)
        }
        return labels
    }

    private static func sourceLabel(from source: String) -> String {
        if source.hasPrefix("registry+") {
            return sanitizedLabel(String(source.dropFirst("registry+".count)))
        }
        if source.hasPrefix("git+") {
            let withoutPrefix = String(source.dropFirst("git+".count))
            let repository = withoutPrefix.split(separator: "?").first.map(String.init) ?? withoutPrefix
            return sanitizedLabel(repository)
        }
        return sanitizedLabel(source)
    }

    private static func unquoted(_ value: String) -> String {
        var text = value
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

    private struct PackageRecord {
        var name: String
        var version: String?
        var source: String?
        var checksum: String?

        init?(fields: [String: String]) {
            guard let name = fields["name"], !name.isEmpty else { return nil }
            self.name = name
            self.version = fields["version"]
            self.source = fields["source"]
            self.checksum = fields["checksum"]
        }

        var label: String {
            ToolArtifactCargoLockPreviewBuilder.sanitizedLabel(version.map { "\(name)@\($0)" } ?? name)
        }
    }

    private static let trackedKeys: Set<String> = ["name", "version", "source", "checksum"]
    private static let byteLimit = 512 * 1_024
    private static let previewLabelLimit = 6
    private static let characterLimit = 120
}
