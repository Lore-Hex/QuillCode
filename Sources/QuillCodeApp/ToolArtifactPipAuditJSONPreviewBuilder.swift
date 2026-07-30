import Foundation

enum ToolArtifactPipAuditJSONPreviewBuilder {
    static func pipAuditJSONPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactPipAuditJSONPreview? {
        guard kind == .file,
              let documentPreview = ToolArtifactDocumentPreviewBuilder.documentPreview(for: value, kind: kind),
              documentPreview.kind == .data,
              documentPreview.extensionLabel.lowercased() == "json",
              let fileURL = localArtifactFileURL(for: value)
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
            let root = try JSONSerialization.jsonObject(with: data, options: [])
            return preview(from: root, byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize))
        } catch {
            return nil
        }
    }

    private static func preview(from root: Any, byteSizeLabel: String?) -> ToolArtifactPipAuditJSONPreview? {
        let dependencies: [[String: Any]]
        if let object = root as? [String: Any],
           let objectDependencies = object["dependencies"] as? [[String: Any]]
        {
            dependencies = objectDependencies
        } else if let array = root as? [[String: Any]] {
            dependencies = array
        } else {
            return nil
        }

        guard !dependencies.isEmpty,
              dependencies.allSatisfy(hasPipAuditDependencyShape)
        else {
            return nil
        }

        var vulnerablePackageLabels: [String] = []
        var vulnerabilityLabels: [String] = []
        var vulnerablePackageCount = 0
        var vulnerabilityCount = 0
        var fixableCount = 0

        for dependency in dependencies {
            let vulnerabilities = dependency["vulns"] as? [[String: Any]] ?? []
            guard !vulnerabilities.isEmpty else { continue }
            vulnerablePackageCount += 1
            vulnerabilityCount += vulnerabilities.count
            if let package = packageLabel(from: dependency) {
                appendUnique(package, to: &vulnerablePackageLabels, limit: previewLimit)
            }
            for vulnerability in vulnerabilities {
                if hasFixVersion(vulnerability) {
                    fixableCount += 1
                }
                if let label = vulnerabilityLabel(from: vulnerability) {
                    appendUnique(label, to: &vulnerabilityLabels, limit: previewLimit)
                }
            }
        }

        guard vulnerabilityCount > 0 else { return nil }

        return ToolArtifactPipAuditJSONPreview(
            dependencyCount: dependencies.count,
            vulnerablePackageCount: vulnerablePackageCount,
            vulnerabilityCount: vulnerabilityCount,
            fixableVulnerabilityCount: fixableCount,
            byteSizeLabel: byteSizeLabel,
            packagePreviewLabels: vulnerablePackageLabels,
            vulnerabilityPreviewLabels: vulnerabilityLabels
        )
    }

    private static func hasPipAuditDependencyShape(_ dependency: [String: Any]) -> Bool {
        guard stringValue(dependency["name"]) != nil,
              stringValue(dependency["version"]) != nil,
              let vulnerabilities = dependency["vulns"] as? [[String: Any]]
        else {
            return false
        }
        return vulnerabilities.allSatisfy(hasPipAuditVulnerabilityShape)
    }

    private static func hasPipAuditVulnerabilityShape(_ vulnerability: [String: Any]) -> Bool {
        guard stringValue(vulnerability["id"]) != nil else { return false }
        return vulnerability["fix_versions"] == nil
            || vulnerability["fix_versions"] is [String]
            || vulnerability["fix_versions"] is [Any]
    }

    private static func packageLabel(from dependency: [String: Any]) -> String? {
        guard let name = stringValue(dependency["name"]) else { return nil }
        let version = stringValue(dependency["version"]).map { " \($0)" } ?? ""
        let vulnerabilities = dependency["vulns"] as? [[String: Any]] ?? []
        let vulnerabilityLabel = " · \(vulnerabilities.count) vulnerabilit\(vulnerabilities.count == 1 ? "y" : "ies")"
        return sanitizedLabel("\(name)\(version)\(vulnerabilityLabel)")
    }

    private static func vulnerabilityLabel(from vulnerability: [String: Any]) -> String? {
        guard let id = stringValue(vulnerability["id"]) else { return nil }
        let aliases = stringArray(vulnerability["aliases"])
        let aliasLabel = aliases.first.map { " · \($0)" } ?? ""
        let fixVersions = stringArray(vulnerability["fix_versions"])
        let fixLabel = fixVersions.first.map { " · fixed in \($0)" } ?? ""
        return sanitizedLabel("\(id)\(aliasLabel)\(fixLabel)")
    }

    private static func hasFixVersion(_ vulnerability: [String: Any]) -> Bool {
        !stringArray(vulnerability["fix_versions"]).isEmpty
    }

    private static func appendUnique(_ value: String, to values: inout [String], limit: Int) {
        guard values.count < limit, !values.contains(value) else { return }
        values.append(value)
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

    private static func stringArray(_ value: Any?) -> [String] {
        guard let values = value as? [Any] else { return [] }
        return values.compactMap(stringValue)
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func sanitizedLabel(_ value: String) -> String {
        let collapsedWhitespace = value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((collapsedWhitespace.isEmpty ? "Unknown" : collapsedWhitespace).prefix(characterLimit))
    }

    private static let byteLimit = 512 * 1_024
    private static let previewLimit = 6
    private static let characterLimit = 96
}
