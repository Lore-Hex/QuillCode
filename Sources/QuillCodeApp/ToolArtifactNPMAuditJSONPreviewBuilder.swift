import Foundation

enum ToolArtifactNPMAuditJSONPreviewBuilder {
    static func npmAuditJSONPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactNPMAuditJSONPreview? {
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
            guard let object = root as? [String: Any] else { return nil }
            return preview(from: object, byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize))
        } catch {
            return nil
        }
    }

    private static func preview(
        from object: [String: Any],
        byteSizeLabel: String?
    ) -> ToolArtifactNPMAuditJSONPreview? {
        guard isNPMAuditReport(object) else { return nil }
        let vulnerabilityCounts = severityCounts(from: object)
        let dependencyCount = dependencyCount(from: object)
        let vulnerablePackages = vulnerablePackageLabels(from: object)
        return ToolArtifactNPMAuditJSONPreview(
            vulnerabilityCounts: vulnerabilityCounts,
            dependencyCount: dependencyCount,
            byteSizeLabel: byteSizeLabel,
            packagePreviewLabels: vulnerablePackages
        )
    }

    private static func isNPMAuditReport(_ object: [String: Any]) -> Bool {
        let version = intValue(object["auditReportVersion"])
        let metadata = object["metadata"] as? [String: Any]
        let hasVulnerabilitiesObject = object["vulnerabilities"] is [String: Any]
        let hasAdvisoriesObject = object["advisories"] is [String: Any]
        return version != nil
            && metadata != nil
            && (hasVulnerabilitiesObject || hasAdvisoriesObject)
    }

    private static func severityCounts(from object: [String: Any]) -> [ToolArtifactNPMAuditSeverityCount] {
        let vulnerabilities = (object["metadata"] as? [String: Any])?["vulnerabilities"] as? [String: Any] ?? [:]
        return severityOrder.compactMap { severity in
            guard let count = intValue(vulnerabilities[severity]), count > 0 else { return nil }
            return ToolArtifactNPMAuditSeverityCount(severity: severity.capitalized, count: count)
        }
    }

    private static func dependencyCount(from object: [String: Any]) -> Int? {
        let dependencies = (object["metadata"] as? [String: Any])?["dependencies"] as? [String: Any]
        let total = intValue(dependencies?["total"])
        return total.flatMap { $0 > 0 ? $0 : nil }
    }

    private static func vulnerablePackageLabels(from object: [String: Any]) -> [String] {
        if let vulnerabilities = object["vulnerabilities"] as? [String: Any] {
            return Array(
                vulnerabilities
                    .compactMap(vulnerabilityLabel)
                    .sorted(by: vulnerabilitySort)
                    .map(\.label)
                    .prefix(previewLimit)
            )
        }
        if let advisories = object["advisories"] as? [String: Any] {
            return Array(
                advisories
                    .values
                    .compactMap(advisoryLabel)
                    .sorted(by: vulnerabilitySort)
                    .map(\.label)
                    .prefix(previewLimit)
            )
        }
        return []
    }

    private static func vulnerabilityLabel(name: String, value: Any) -> PackageFinding? {
        guard let vulnerability = value as? [String: Any] else { return nil }
        let packageName = stringValue(vulnerability["name"]) ?? name
        let severity = stringValue(vulnerability["severity"])?.lowercased()
        let severityLabel = severity.map { " · \($0)" } ?? ""
        let viaCount = (vulnerability["via"] as? [Any])?.count
        let viaLabel = viaCount.flatMap { $0 > 0 ? " · \($0) finding\($0 == 1 ? "" : "s")" : nil } ?? ""
        return PackageFinding(
            packageName: packageName,
            severityRank: severityRank(severity),
            label: sanitizedLabel("\(packageName)\(severityLabel)\(viaLabel)")
        )
    }

    private static func advisoryLabel(_ value: Any) -> PackageFinding? {
        guard let advisory = value as? [String: Any] else { return nil }
        let moduleName = stringValue(advisory["module_name"]) ?? stringValue(advisory["name"])
        guard let moduleName else { return nil }
        let severity = stringValue(advisory["severity"])?.lowercased()
        let severityLabel = severity.map { " · \($0)" } ?? ""
        return PackageFinding(
            packageName: moduleName,
            severityRank: severityRank(severity),
            label: sanitizedLabel("\(moduleName)\(severityLabel)")
        )
    }

    private static func vulnerabilitySort(lhs: PackageFinding, rhs: PackageFinding) -> Bool {
        if lhs.severityRank != rhs.severityRank {
            return lhs.severityRank < rhs.severityRank
        }
        return lhs.packageName.localizedCaseInsensitiveCompare(rhs.packageName) == .orderedAscending
    }

    private static func severityRank(_ severity: String?) -> Int {
        guard let severity, let index = severityOrder.firstIndex(of: severity) else { return severityOrder.count }
        return index
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

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let int as Int:
            return int
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string)
        default:
            return nil
        }
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
        return String((collapsedWhitespace.isEmpty ? "Unknown package" : collapsedWhitespace).prefix(characterLimit))
    }

    private static let severityOrder = ["critical", "high", "moderate", "low", "info"]
    private static let byteLimit = 512 * 1_024
    private static let previewLimit = 6
    private static let characterLimit = 96

    private struct PackageFinding {
        var packageName: String
        var severityRank: Int
        var label: String
    }
}
