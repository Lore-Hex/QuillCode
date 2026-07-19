import Foundation

enum ToolArtifactSwiftPMPackageResolvedPreviewBuilder {
    static func packageResolvedPreview(
        for value: String,
        kind: ToolArtifactKind
    ) -> ToolArtifactSwiftPMPackageResolvedPreview? {
        guard kind == .file,
              let fileURL = localArtifactFileURL(for: value),
              fileURL.lastPathComponent.lowercased() == "package.resolved"
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
                  let pins = root["pins"] as? [[String: Any]]
            else {
                return nil
            }
            let preview = preview(
                from: root,
                pins: pins,
                byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
            )
            return preview.hasDisplayContent ? preview : nil
        } catch {
            return nil
        }
    }

    private static func preview(
        from root: [String: Any],
        pins: [[String: Any]],
        byteSizeLabel: String?
    ) -> ToolArtifactSwiftPMPackageResolvedPreview {
        let records = pins.compactMap(PinRecord.init(pin:))
        return ToolArtifactSwiftPMPackageResolvedPreview(
            schemaVersion: schemaVersionLabel(root["version"]),
            pinCount: pins.count,
            versionedPinCount: records.filter { $0.version != nil }.count,
            branchPinCount: records.filter { $0.branch != nil }.count,
            revisionOnlyPinCount: records.filter { $0.version == nil && $0.branch == nil && $0.revision != nil }.count,
            sourceHostLabels: sourceHostLabels(from: records),
            pinPreviewLabels: Array(records.prefix(previewLabelLimit)).map(\.label),
            byteSizeLabel: byteSizeLabel
        )
    }

    private static func sourceHostLabels(from records: [PinRecord]) -> [String] {
        var labels: [String] = []
        var seen = Set<String>()
        for record in records {
            guard labels.count < previewLabelLimit,
                  let location = record.location,
                  let host = URL(string: location)?.host?.lowercased(),
                  !seen.contains(host)
            else {
                continue
            }
            seen.insert(host)
            labels.append(sanitizedLabel(host))
        }
        return labels
    }

    private static func schemaVersionLabel(_ value: Any?) -> String? {
        if let string = stringValue(value) {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let label = sanitizedLabel(string)
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

    private struct PinRecord {
        var identity: String
        var location: String?
        var version: String?
        var branch: String?
        var revision: String?

        init?(pin: [String: Any]) {
            let state = pin["state"] as? [String: Any] ?? [:]
            guard let identity = Self.identity(from: pin) else { return nil }
            self.identity = identity
            self.location = ToolArtifactSwiftPMPackageResolvedPreviewBuilder.stringValue(pin["location"])
                ?? ToolArtifactSwiftPMPackageResolvedPreviewBuilder.stringValue(pin["repositoryURL"])
            self.version = ToolArtifactSwiftPMPackageResolvedPreviewBuilder.stringValue(state["version"])
            self.branch = ToolArtifactSwiftPMPackageResolvedPreviewBuilder.stringValue(state["branch"])
            self.revision = ToolArtifactSwiftPMPackageResolvedPreviewBuilder.stringValue(state["revision"])
        }

        var label: String {
            var label = identity
            if let version {
                label += "@\(version)"
            } else if let branch {
                label += " · \(branch)"
            } else if let revision {
                label += " · \(revision.prefix(12))"
            }
            return ToolArtifactSwiftPMPackageResolvedPreviewBuilder.sanitizedLabel(label)
        }

        private static func identity(from pin: [String: Any]) -> String? {
            if let identity = ToolArtifactSwiftPMPackageResolvedPreviewBuilder.stringValue(pin["identity"]) {
                return identity
            }
            if let package = ToolArtifactSwiftPMPackageResolvedPreviewBuilder.stringValue(pin["package"]) {
                return package
            }
            if let location = ToolArtifactSwiftPMPackageResolvedPreviewBuilder.stringValue(pin["location"]),
               let lastComponent = location.split(separator: "/").last {
                return String(lastComponent)
            }
            if let repositoryURL = ToolArtifactSwiftPMPackageResolvedPreviewBuilder.stringValue(pin["repositoryURL"]),
               let lastComponent = repositoryURL.split(separator: "/").last {
                return String(lastComponent)
            }
            return nil
        }
    }

    private static let byteLimit = 512 * 1_024
    private static let previewLabelLimit = 6
    private static let characterLimit = 120
}
