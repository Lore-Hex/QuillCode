import Foundation
import Yams

enum ToolArtifactPNPMLockfilePreviewBuilder {
    static func pnpmLockfilePreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactPNPMLockfilePreview? {
        guard kind == .file,
              let fileURL = localArtifactFileURL(for: value),
              fileURL.lastPathComponent.lowercased() == "pnpm-lock.yaml"
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
                  let text = String(data: data, encoding: .utf8),
                  let root = try Yams.compose(yaml: text),
                  case .mapping = root,
                  scalarValue(forKey: "lockfileVersion", in: root) != nil
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

    private static func preview(from root: Node, byteSizeLabel: String?) -> ToolArtifactPNPMLockfilePreview {
        let importerRecords = mappingRecords(from: mappingValue(forKey: "importers", in: root))
        let packageRecords = packageRecords(from: mappingValue(forKey: "packages", in: root))
        let dependencyCount = importerRecords.reduce(0) { $0 + $1.dependencyCount }
        return ToolArtifactPNPMLockfilePreview(
            lockfileVersion: scalarValue(forKey: "lockfileVersion", in: root),
            importerCount: importerRecords.count,
            packageCount: packageRecords.count,
            dependencyCount: dependencyCount,
            integrityCount: packageRecords.filter { $0.integrity != nil }.count,
            resolvedHostLabels: resolvedHostLabels(from: packageRecords),
            packagePreviewLabels: Array(packageRecords.prefix(previewLabelLimit)).map(\.label),
            importerPreviewLabels: Array(importerRecords.prefix(previewLabelLimit)).map(\.label),
            byteSizeLabel: byteSizeLabel
        )
    }

    private static func mappingRecords(from node: Node?) -> [ImporterRecord] {
        guard case .mapping(let mapping) = node else { return [] }
        return mapping.compactMap { pair in
            guard let label = scalarLabel(pair.key) else { return nil }
            let dependencyCount = dependencyCount(in: pair.value)
            return ImporterRecord(label: label, dependencyCount: dependencyCount)
        }
        .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    private static func dependencyCount(in importer: Node) -> Int {
        dependencyKeys.reduce(0) { count, key in
            guard case .mapping(let dependencies) = mappingValue(forKey: key, in: importer) else {
                return count
            }
            return count + dependencies.count
        }
    }

    private static func packageRecords(from node: Node?) -> [PackageRecord] {
        guard case .mapping(let mapping) = node else { return [] }
        return mapping.compactMap { pair in
            guard let rawName = scalarLabel(pair.key) else { return nil }
            let resolution = mappingValue(forKey: "resolution", in: pair.value)
            let integrity = scalarValue(forKey: "integrity", in: resolution)
            let tarball = scalarValue(forKey: "tarball", in: resolution)
            return PackageRecord(
                rawName: rawName,
                integrity: integrity,
                tarball: tarball
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func resolvedHostLabels(from packages: [PackageRecord]) -> [String] {
        var labels: [String] = []
        var seen = Set<String>()
        for package in packages {
            guard labels.count < previewLabelLimit,
                  let tarball = package.tarball,
                  let host = URL(string: tarball)?.host?.lowercased(),
                  !seen.contains(host)
            else {
                continue
            }
            seen.insert(host)
            labels.append(sanitizedLabel(host))
        }
        return labels
    }

    private static func mappingValue(forKey key: String, in node: Node?) -> Node? {
        guard case .mapping(let mapping) = node else { return nil }
        return mapping.first { scalarLabel($0.key) == key }?.value
    }

    private static func scalarValue(forKey key: String, in node: Node?) -> String? {
        guard let value = mappingValue(forKey: key, in: node) else { return nil }
        return scalarLabel(value)
    }

    private static func scalarLabel(_ node: Node) -> String? {
        guard case .scalar(let scalar) = node else { return nil }
        let label = sanitizedLabel(scalar.string)
        return label.isEmpty ? nil : label
    }

    private static func packageName(from rawName: String) -> String {
        var text = rawName
        if text.hasPrefix("/") {
            text.removeFirst()
        }
        if let peerSuffix = text.firstIndex(of: "(") {
            text = String(text[..<peerSuffix])
        }
        if let lastAt = text.lastIndex(of: "@"), lastAt != text.startIndex {
            text = String(text[..<lastAt])
        }
        return sanitizedLabel(text)
    }

    private static func packageVersion(from rawName: String) -> String? {
        var text = rawName
        if let peerSuffix = text.firstIndex(of: "(") {
            text = String(text[..<peerSuffix])
        }
        guard let lastAt = text.lastIndex(of: "@"), lastAt != text.startIndex else { return nil }
        let version = text[text.index(after: lastAt)...]
        let label = sanitizedLabel(String(version))
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

    private struct ImporterRecord {
        var label: String
        var dependencyCount: Int
    }

    private struct PackageRecord {
        var rawName: String
        var integrity: String?
        var tarball: String?

        var name: String {
            ToolArtifactPNPMLockfilePreviewBuilder.packageName(from: rawName)
        }

        var label: String {
            let name = ToolArtifactPNPMLockfilePreviewBuilder.packageName(from: rawName)
            guard let version = ToolArtifactPNPMLockfilePreviewBuilder.packageVersion(from: rawName) else {
                return name
            }
            return ToolArtifactPNPMLockfilePreviewBuilder.sanitizedLabel("\(name)@\(version)")
        }
    }

    private static let dependencyKeys = ["dependencies", "devDependencies", "optionalDependencies"]
    private static let byteLimit = 512 * 1_024
    private static let previewLabelLimit = 6
    private static let characterLimit = 120
}
