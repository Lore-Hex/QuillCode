import Foundation
import QuillCodePersistence

enum ToolArtifactTOMLPreviewBuilder {
    static func tomlPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactTOMLPreview? {
        guard kind == .file,
              let documentPreview = ToolArtifactDocumentPreviewBuilder.documentPreview(for: value, kind: kind),
              documentPreview.kind == .data,
              documentPreview.extensionLabel.lowercased() == "toml",
              let fileURL = localArtifactFileURL(for: value)
        else {
            return nil
        }

        do {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard resourceValues.isRegularFile == true else { return nil }
            let fileSize = max(resourceValues.fileSize ?? 0, 0)
            guard fileSize > 0, fileSize <= byteLimit else { return nil }
            let snapshot = try ConfigDocumentStore(fileURL: fileURL).loadSnapshot()
            let preview = preview(from: snapshot.document.values, fileSize: fileSize)
            return preview.hasDisplayContent ? preview : nil
        } catch {
            return nil
        }
    }

    private static func preview(from values: [String: ConfigValue], fileSize: Int) -> ToolArtifactTOMLPreview {
        let keys = values.keys.sorted()
        let counts = valueCounts(in: Array(values.values))
        return ToolArtifactTOMLPreview(
            topLevelKeyCount: keys.count,
            tableCount: counts.tables,
            arrayCount: counts.arrays,
            scalarCount: counts.scalars,
            keyPreviewLabel: previewLabel(for: keys),
            keyPreviewLabels: previewLabels(for: keys),
            byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
        )
    }

    private static func valueCounts(in values: [ConfigValue]) -> (tables: Int, arrays: Int, scalars: Int) {
        var tables = 0
        var arrays = 0
        var scalars = 0
        for value in values {
            switch value {
            case .object(let object):
                tables += 1
                let nested = valueCounts(in: Array(object.values))
                tables += nested.tables
                arrays += nested.arrays
                scalars += nested.scalars
            case .array(let array):
                arrays += 1
                let nested = valueCounts(in: array)
                tables += nested.tables
                arrays += nested.arrays
                scalars += nested.scalars
            case .string, .integer, .number, .bool, .offsetDateTime, .localDateTime, .localDate, .localTime:
                scalars += 1
            }
        }
        return (tables, arrays, scalars)
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
