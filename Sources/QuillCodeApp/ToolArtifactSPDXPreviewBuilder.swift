import Foundation

enum ToolArtifactSPDXPreviewBuilder {
    static func spdxPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactSPDXPreview? {
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
                  isSPDXDocument(root)
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

    private static func isSPDXDocument(_ root: [String: Any]) -> Bool {
        guard let version = stringValue(root["spdxVersion"])?.uppercased(),
              version.hasPrefix("SPDX-")
        else {
            return false
        }
        return stringValue(root["SPDXID"]) != nil
            || stringValue(root["documentNamespace"]) != nil
            || root["packages"] is [[String: Any]]
            || root["files"] is [[String: Any]]
    }

    private static func preview(from root: [String: Any], byteSizeLabel: String?) -> ToolArtifactSPDXPreview {
        let packages = root["packages"] as? [[String: Any]] ?? []
        let files = root["files"] as? [[String: Any]] ?? []
        let relationships = root["relationships"] as? [[String: Any]] ?? []
        let extractedLicenses = root["hasExtractedLicensingInfos"] as? [[String: Any]] ?? []
        let creators = (root["creationInfo"] as? [String: Any])?["creators"] as? [String] ?? []
        let licenseLabels = licensePreviewLabels(from: packages, extractedLicenses: extractedLicenses)

        return ToolArtifactSPDXPreview(
            specVersion: stringValue(root["spdxVersion"]),
            documentName: stringValue(root["name"]),
            documentNamespace: stringValue(root["documentNamespace"]),
            packageCount: packages.count,
            fileCount: files.count,
            relationshipCount: relationships.count,
            extractedLicenseCount: extractedLicenses.count,
            creatorCount: creators.count,
            byteSizeLabel: byteSizeLabel,
            packagePreviewLabels: previewLabels(from: packages),
            licensePreviewLabels: licenseLabels
        )
    }

    private static func previewLabels(from packages: [[String: Any]]) -> [String] {
        Array(packages.compactMap(packageLabel(from:)).prefix(previewLabelLimit))
    }

    private static func packageLabel(from package: [String: Any]) -> String? {
        guard let name = stringValue(package["name"]) else { return nil }
        let version = stringValue(package["versionInfo"])
        let identifier = stringValue(package["SPDXID"])
        var label = version.map { "\(name)@\($0)" } ?? name
        if let identifier {
            label += " · \(identifier)"
        }
        return sanitizedLabel(label)
    }

    private static func licensePreviewLabels(
        from packages: [[String: Any]],
        extractedLicenses: [[String: Any]]
    ) -> [String] {
        var labels: [String] = []
        var seen = Set<String>()
        for package in packages {
            appendLicenseLabel(stringValue(package["licenseConcluded"]), labels: &labels, seen: &seen)
            appendLicenseLabel(stringValue(package["licenseDeclared"]), labels: &labels, seen: &seen)
            guard labels.count < previewLabelLimit else { return labels }
        }
        for license in extractedLicenses {
            appendLicenseLabel(stringValue(license["licenseId"]), labels: &labels, seen: &seen)
            guard labels.count < previewLabelLimit else { return labels }
        }
        return labels
    }

    private static func appendLicenseLabel(_ label: String?, labels: inout [String], seen: inout Set<String>) {
        guard labels.count < previewLabelLimit,
              let label,
              label != "NOASSERTION",
              label != "NONE",
              !seen.contains(label)
        else {
            return
        }
        seen.insert(label)
        labels.append(label)
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
