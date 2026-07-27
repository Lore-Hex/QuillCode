import Foundation

enum ToolArtifactCargoAuditJSONPreviewBuilder {
    static func cargoAuditJSONPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactCargoAuditJSONPreview? {
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
    ) -> ToolArtifactCargoAuditJSONPreview? {
        guard let vulnerabilities = object["vulnerabilities"] as? [String: Any],
              let list = vulnerabilities["list"] as? [[String: Any]],
              let reportedCount = intValue(vulnerabilities["count"]) ?? optionalCount(from: list),
              vulnerabilities["found"] is Bool || reportedCount > 0,
              list.allSatisfy(hasCargoAuditVulnerabilityShape)
        else {
            return nil
        }

        let packageLabels = Array(
            list
                .compactMap(packageLabel)
                .sorted()
                .prefix(previewLimit)
        )
        let advisoryLabels = Array(
            list
                .compactMap(advisoryLabel)
                .sorted()
                .prefix(previewLimit)
        )
        let yankedCount = warningCount(in: object, key: "yanked")
        let unmaintainedCount = warningCount(in: object, key: "unmaintained")

        guard reportedCount > 0 || yankedCount > 0 || unmaintainedCount > 0 else { return nil }

        return ToolArtifactCargoAuditJSONPreview(
            vulnerabilityCount: reportedCount,
            yankedWarningCount: yankedCount,
            unmaintainedWarningCount: unmaintainedCount,
            byteSizeLabel: byteSizeLabel,
            packagePreviewLabels: packageLabels,
            advisoryPreviewLabels: advisoryLabels
        )
    }

    private static func hasCargoAuditVulnerabilityShape(_ value: [String: Any]) -> Bool {
        guard let advisory = value["advisory"] as? [String: Any],
              stringValue(advisory["id"]) != nil,
              stringValue(advisory["package"]) != nil || stringValue((value["package"] as? [String: Any])?["name"]) != nil
        else {
            return false
        }
        return value["package"] is [String: Any] || stringValue(advisory["title"]) != nil
    }

    private static func packageLabel(from value: [String: Any]) -> String? {
        let advisory = value["advisory"] as? [String: Any]
        let package = value["package"] as? [String: Any]
        let name = stringValue(package?["name"]) ?? stringValue(advisory?["package"])
        guard let name else { return nil }
        let version = stringValue(package?["version"]).map { " \($0)" } ?? ""
        return sanitizedLabel("\(name)\(version)")
    }

    private static func advisoryLabel(from value: [String: Any]) -> String? {
        guard let advisory = value["advisory"] as? [String: Any],
              let id = stringValue(advisory["id"])
        else {
            return nil
        }
        let title = stringValue(advisory["title"]).map { " · \($0)" } ?? ""
        return sanitizedLabel("\(id)\(title)")
    }

    private static func warningCount(in object: [String: Any], key: String) -> Int {
        guard let warnings = object["warnings"] as? [String: Any],
              let warning = warnings[key] as? [[String: Any]]
        else {
            return 0
        }
        return warning.count
    }

    private static func optionalCount(from list: [[String: Any]]) -> Int? {
        list.isEmpty ? nil : list.count
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
        return String((collapsedWhitespace.isEmpty ? "Unknown" : collapsedWhitespace).prefix(characterLimit))
    }

    private static let byteLimit = 512 * 1_024
    private static let previewLimit = 6
    private static let characterLimit = 96
}
