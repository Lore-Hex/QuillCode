import Foundation

enum ToolArtifactNotebookPreviewBuilder {
    static func notebookPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactNotebookPreview? {
        guard kind == .file,
              ToolArtifactValueClassifier.pathExtension(for: value) == "ipynb",
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
            return preview(from: root, fileSize: fileSize)
        } catch {
            return nil
        }
    }

    private static func preview(from root: Any, fileSize: Int) -> ToolArtifactNotebookPreview? {
        guard let object = root as? [String: Any],
              let cells = object["cells"] as? [[String: Any]]
        else {
            return nil
        }

        var codeCellCount = 0
        var markdownCellCount = 0
        var rawCellCount = 0
        for cell in cells {
            switch cell["cell_type"] as? String {
            case "code":
                codeCellCount += 1
            case "markdown":
                markdownCellCount += 1
            case "raw":
                rawCellCount += 1
            default:
                rawCellCount += 1
            }
        }

        let versionLabel = notebookVersionLabel(from: object)
        let languageLabel = languageLabel(from: object)
        let preview = ToolArtifactNotebookPreview(
            notebookVersionLabel: versionLabel,
            languageLabel: languageLabel,
            codeCellCount: codeCellCount,
            markdownCellCount: markdownCellCount,
            rawCellCount: rawCellCount,
            byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
        )
        return preview.hasDisplayContent ? preview : nil
    }

    private static func notebookVersionLabel(from object: [String: Any]) -> String? {
        guard let major = object["nbformat"] else { return nil }
        let minor = object["nbformat_minor"]
        if let major = integerLabel(major), let minor = minor.flatMap(integerLabel) {
            return "\(major).\(minor)"
        }
        return integerLabel(major)
    }

    private static func languageLabel(from object: [String: Any]) -> String? {
        guard let metadata = object["metadata"] as? [String: Any] else { return nil }
        if let languageInfo = metadata["language_info"] as? [String: Any],
           let name = languageInfo["name"] as? String {
            return sanitizedLabel(name)
        }
        if let kernelspec = metadata["kernelspec"] as? [String: Any],
           let language = kernelspec["language"] as? String {
            return sanitizedLabel(language)
        }
        return nil
    }

    private static func integerLabel(_ value: Any) -> String? {
        switch value {
        case let value as Int:
            return String(value)
        case let value as NSNumber:
            return String(value.intValue)
        default:
            return nil
        }
    }

    private static func sanitizedLabel(_ value: String) -> String {
        let collapsedWhitespace = value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((collapsedWhitespace.isEmpty ? "Unknown" : collapsedWhitespace).prefix(labelCharacterLimit))
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
    private static let labelCharacterLimit = 80
}
