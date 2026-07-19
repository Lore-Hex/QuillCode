import Foundation

enum ToolArtifactJSONPreviewBuilder {
    static func jsonPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactJSONPreview? {
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
            let preview = preview(from: root, fileSize: fileSize)
            return preview.hasDisplayContent ? preview : nil
        } catch {
            return nil
        }
    }

    private static func preview(from root: Any, fileSize: Int) -> ToolArtifactJSONPreview {
        if let object = root as? [String: Any] {
            let keys = object.keys.sorted()
            return ToolArtifactJSONPreview(
                rootLabel: "Object",
                keyCount: keys.count,
                keyPreviewLabel: previewLabel(for: keys),
                keyPreviewLabels: previewLabels(for: keys),
                byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
            )
        }
        if let array = root as? [Any] {
            return ToolArtifactJSONPreview(
                rootLabel: "Array",
                itemCount: array.count,
                byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
            )
        }
        return ToolArtifactJSONPreview(
            rootLabel: scalarRootLabel(for: root),
            byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
        )
    }

    private static func previewLabel(for keys: [String]) -> String? {
        guard !keys.isEmpty else { return nil }
        let visibleKeys = keys.prefix(keyPreviewLimit)
        let labels = visibleKeys.map(sanitizedLabel)
        let remainder = keys.count - visibleKeys.count
        return ([labels.joined(separator: ", ")] + (remainder > 0 ? ["+\(remainder) more"] : []))
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private static func previewLabels(for keys: [String]) -> [String] {
        Array(keys.prefix(keyPreviewLimit)).map(sanitizedLabel)
    }

    private static func sanitizedLabel(_ key: String) -> String {
        let collapsedWhitespace = key
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((collapsedWhitespace.isEmpty ? "(empty key)" : collapsedWhitespace).prefix(keyCharacterLimit))
    }

    private static func scalarRootLabel(for root: Any) -> String {
        switch root {
        case is String:
            return "String"
        case is NSNumber:
            return "Scalar"
        case _ as NSNull:
            return "Null"
        default:
            return "Scalar"
        }
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

    private static let byteLimit = 64 * 1_024
    private static let keyPreviewLimit = 6
    private static let keyCharacterLimit = 80
}
