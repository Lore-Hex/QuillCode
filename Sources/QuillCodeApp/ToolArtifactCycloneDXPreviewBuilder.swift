import Foundation

enum ToolArtifactCycloneDXPreviewBuilder {
    static func cycloneDXPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactCycloneDXPreview? {
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
            guard !data.contains(0),
                  let root = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                  stringValue(root["bomFormat"])?.lowercased() == "cyclonedx"
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

    private static func preview(from root: [String: Any], byteSizeLabel: String?) -> ToolArtifactCycloneDXPreview {
        let components = root["components"] as? [[String: Any]] ?? []
        let services = root["services"] as? [[String: Any]] ?? []
        let dependencies = root["dependencies"] as? [[String: Any]] ?? []
        let vulnerabilities = root["vulnerabilities"] as? [[String: Any]] ?? []

        return ToolArtifactCycloneDXPreview(
            specVersion: stringValue(root["specVersion"]),
            serialNumber: stringValue(root["serialNumber"]),
            rootComponentLabel: rootComponentLabel(from: root["metadata"] as? [String: Any]),
            componentCount: components.count,
            serviceCount: services.count,
            dependencyCount: dependencies.count,
            vulnerabilityCount: vulnerabilities.count,
            criticalVulnerabilityCount: vulnerabilityCount("critical", in: vulnerabilities),
            highVulnerabilityCount: vulnerabilityCount("high", in: vulnerabilities),
            mediumVulnerabilityCount: vulnerabilityCount("medium", in: vulnerabilities),
            lowVulnerabilityCount: vulnerabilityCount("low", in: vulnerabilities),
            byteSizeLabel: byteSizeLabel,
            componentPreviewLabels: previewLabels(from: components)
        )
    }

    private static func rootComponentLabel(from metadata: [String: Any]?) -> String? {
        guard let component = metadata?["component"] as? [String: Any] else { return nil }
        return componentLabel(from: component)
    }

    private static func previewLabels(from components: [[String: Any]]) -> [String] {
        Array(components.compactMap(componentLabel(from:)).prefix(previewLabelLimit))
    }

    private static func componentLabel(from component: [String: Any]) -> String? {
        guard let name = stringValue(component["name"]) else { return nil }
        let version = stringValue(component["version"])
        let type = stringValue(component["type"])
        let packageURL = stringValue(component["purl"])
        var label = version.map { "\(name)@\($0)" } ?? name
        if let type {
            label += " · \(type)"
        }
        if let packageURL {
            label += " · \(packageURL)"
        }
        return sanitizedLabel(label)
    }

    private static func vulnerabilityCount(_ severity: String, in vulnerabilities: [[String: Any]]) -> Int {
        vulnerabilities.filter { vulnerability in
            vulnerabilitySeverity(from: vulnerability)?.lowercased() == severity
        }.count
    }

    private static func vulnerabilitySeverity(from vulnerability: [String: Any]) -> String? {
        if let ratings = vulnerability["ratings"] as? [[String: Any]] {
            for rating in ratings {
                if let severity = stringValue(rating["severity"]) {
                    return severity
                }
            }
        }
        return stringValue(vulnerability["severity"])
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        return sanitizedLabel(string)
    }

    private static func sanitizedLabel(_ value: String) -> String? {
        let collapsedWhitespace = value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsedWhitespace.isEmpty else { return nil }
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

    private static let byteLimit = 512 * 1_024
    private static let previewLabelLimit = 6
    private static let characterLimit = 120
}
