import Foundation

enum ToolArtifactPropertyListPreviewBuilder {
    static func propertyListPreview(
        for value: String,
        kind: ToolArtifactKind
    ) -> ToolArtifactPropertyListPreview? {
        guard kind == .file,
              let documentPreview = ToolArtifactDocumentPreviewBuilder.documentPreview(for: value, kind: kind),
              documentPreview.kind == .data,
              documentPreview.extensionLabel.lowercased() == "plist",
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
            var format = PropertyListSerialization.PropertyListFormat.xml
            let root = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: &format
            )
            let preview = preview(from: root, format: format, fileSize: fileSize)
            return preview.hasDisplayContent ? preview : nil
        } catch {
            return nil
        }
    }

    private static func preview(
        from root: Any,
        format: PropertyListSerialization.PropertyListFormat,
        fileSize: Int
    ) -> ToolArtifactPropertyListPreview {
        let counts = valueCounts(in: root)
        if let dictionary = root as? [String: Any] {
            let keys = dictionary.keys.sorted()
            return ToolArtifactPropertyListPreview(
                rootLabel: "Dictionary",
                formatLabel: formatLabel(for: format),
                keyCount: keys.count,
                dictionaryCount: counts.dictionaries,
                arrayCount: counts.arrays,
                scalarCount: counts.scalars,
                keyPreviewLabel: previewLabel(for: keys),
                keyPreviewLabels: previewLabels(for: keys),
                byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
            )
        }
        if let array = root as? [Any] {
            return ToolArtifactPropertyListPreview(
                rootLabel: "Array",
                formatLabel: formatLabel(for: format),
                itemCount: array.count,
                dictionaryCount: counts.dictionaries,
                arrayCount: counts.arrays,
                scalarCount: counts.scalars,
                byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
            )
        }
        return ToolArtifactPropertyListPreview(
            rootLabel: scalarRootLabel(for: root),
            formatLabel: formatLabel(for: format),
            dictionaryCount: counts.dictionaries,
            arrayCount: counts.arrays,
            scalarCount: counts.scalars,
            byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
        )
    }

    private static func valueCounts(in value: Any) -> (dictionaries: Int, arrays: Int, scalars: Int) {
        if let dictionary = value as? [String: Any] {
            return dictionary.values.reduce((dictionaries: 1, arrays: 0, scalars: 0)) { result, value in
                let nested = valueCounts(in: value)
                return (
                    dictionaries: result.dictionaries + nested.dictionaries,
                    arrays: result.arrays + nested.arrays,
                    scalars: result.scalars + nested.scalars
                )
            }
        }
        if let array = value as? [Any] {
            return array.reduce((dictionaries: 0, arrays: 1, scalars: 0)) { result, value in
                let nested = valueCounts(in: value)
                return (
                    dictionaries: result.dictionaries + nested.dictionaries,
                    arrays: result.arrays + nested.arrays,
                    scalars: result.scalars + nested.scalars
                )
            }
        }
        return (dictionaries: 0, arrays: 0, scalars: 1)
    }

    private static func formatLabel(for format: PropertyListSerialization.PropertyListFormat) -> String {
        switch format {
        case .binary:
            return "Binary PLIST"
        case .xml:
            return "XML PLIST"
        case .openStep:
            return "OpenStep PLIST"
        @unknown default:
            return "PLIST"
        }
    }

    private static func scalarRootLabel(for root: Any) -> String {
        switch root {
        case is String:
            return "String"
        case is NSNumber:
            return "Scalar"
        case is Date:
            return "Date"
        case is Data:
            return "Data"
        default:
            return "Scalar"
        }
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
