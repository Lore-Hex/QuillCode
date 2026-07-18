import Foundation

enum ToolArtifactHARPreviewBuilder {
    static func harPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactHARPreview? {
        guard kind == .file,
              let documentPreview = ToolArtifactDocumentPreviewBuilder.documentPreview(for: value, kind: kind),
              documentPreview.kind == .data,
              documentPreview.extensionLabel.lowercased() == "har",
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
            guard let preview = preview(from: root, fileSize: fileSize) else { return nil }
            return preview.hasDisplayContent ? preview : nil
        } catch {
            return nil
        }
    }

    private static func preview(from root: Any, fileSize: Int) -> ToolArtifactHARPreview? {
        guard let object = root as? [String: Any],
              let log = object["log"] as? [String: Any],
              let entries = log["entries"] as? [[String: Any]]
        else {
            return nil
        }

        let version = (log["version"] as? String).flatMap(sanitizedOptionalLabel)
        let creator = creatorLabel(from: log["creator"] as? [String: Any])
        var methods = Set<String>()
        var statusGroups = Set<String>()
        var hosts = Set<String>()

        for entry in entries.prefix(entryScanLimit) {
            if let request = entry["request"] as? [String: Any] {
                if let method = sanitizedOptionalLabel(request["method"] as? String) {
                    methods.insert(method.uppercased())
                }
                if let url = request["url"] as? String,
                   let host = hostLabel(from: url) {
                    hosts.insert(host)
                }
            }
            if let response = entry["response"] as? [String: Any],
               let status = response["status"] {
                if let group = statusGroupLabel(from: status) {
                    statusGroups.insert(group)
                }
            }
        }

        return ToolArtifactHARPreview(
            versionLabel: version,
            creatorLabel: creator,
            entryCount: entries.count,
            methodLabels: cappedSortedLabels(methods),
            statusGroupLabels: cappedSortedLabels(statusGroups),
            hostPreviewLabels: cappedSortedLabels(hosts),
            byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
        )
    }

    private static func creatorLabel(from creator: [String: Any]?) -> String? {
        guard let creator else { return nil }
        let name = sanitizedOptionalLabel(creator["name"] as? String)
        let version = sanitizedOptionalLabel(creator["version"] as? String)
        switch (name, version) {
        case let (name?, version?):
            return "\(name) \(version)"
        case let (name?, nil):
            return name
        case let (nil, version?):
            return version
        case (nil, nil):
            return nil
        }
    }

    private static func hostLabel(from urlString: String) -> String? {
        guard let url = URL(string: urlString),
              let host = url.host
        else {
            return nil
        }
        return sanitizedOptionalLabel(host.lowercased())
    }

    private static func statusGroupLabel(from value: Any) -> String? {
        let status: Int?
        if let intValue = value as? Int {
            status = intValue
        } else if let numberValue = value as? NSNumber {
            status = numberValue.intValue
        } else {
            status = nil
        }
        guard let status, status >= 100, status <= 599 else { return nil }
        return "\(status / 100)xx"
    }

    private static func cappedSortedLabels(_ labels: Set<String>) -> [String] {
        labels.sorted().prefix(labelPreviewLimit).map { String($0.prefix(labelCharacterLimit)) }
    }

    private static func sanitizedOptionalLabel(_ value: String?) -> String? {
        guard let value else { return nil }
        let collapsed = value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(labelCharacterLimit))
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

    private static let byteLimit = 256 * 1_024
    private static let entryScanLimit = 200
    private static let labelPreviewLimit = 6
    private static let labelCharacterLimit = 80
}
