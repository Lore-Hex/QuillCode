import Foundation
import Yams

enum ToolArtifactYAMLPreviewBuilder {
    static func yamlPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactYAMLPreview? {
        guard kind == .file,
              let documentPreview = ToolArtifactDocumentPreviewBuilder.documentPreview(for: value, kind: kind),
              documentPreview.kind == .data,
              supportedExtensions.contains(documentPreview.extensionLabel.lowercased()),
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
                  let text = String(data: data, encoding: .utf8),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let root = try Yams.compose(yaml: text)
            else {
                return nil
            }
            let preview = preview(
                from: root,
                formatLabel: documentPreview.extensionLabel.uppercased(),
                fileSize: fileSize
            )
            return preview.hasDisplayContent ? preview : nil
        } catch {
            return nil
        }
    }

    private static func preview(
        from root: Node,
        formatLabel: String,
        fileSize: Int
    ) -> ToolArtifactYAMLPreview {
        let counts = valueCounts(in: root)
        switch root {
        case .mapping(let mapping):
            let keys = mapping.compactMap { pair in scalarKeyLabel(pair.key) }.sorted()
            return ToolArtifactYAMLPreview(
                formatLabel: formatLabel,
                rootLabel: "Mapping",
                keyCount: keys.count,
                mappingCount: counts.mappings,
                sequenceCount: counts.sequences,
                scalarCount: counts.scalars,
                keyPreviewLabel: previewLabel(for: keys),
                keyPreviewLabels: previewLabels(for: keys),
                byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
            )
        case .sequence(let sequence):
            return ToolArtifactYAMLPreview(
                formatLabel: formatLabel,
                rootLabel: "Sequence",
                itemCount: sequence.count,
                mappingCount: counts.mappings,
                sequenceCount: counts.sequences,
                scalarCount: counts.scalars,
                byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
            )
        case .scalar:
            return ToolArtifactYAMLPreview(
                formatLabel: formatLabel,
                rootLabel: "Scalar",
                mappingCount: counts.mappings,
                sequenceCount: counts.sequences,
                scalarCount: counts.scalars,
                byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
            )
        case .alias:
            return ToolArtifactYAMLPreview(
                formatLabel: formatLabel,
                rootLabel: "Alias",
                mappingCount: counts.mappings,
                sequenceCount: counts.sequences,
                scalarCount: counts.scalars,
                byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
            )
        }
    }

    private static func valueCounts(in node: Node) -> (mappings: Int, sequences: Int, scalars: Int) {
        switch node {
        case .mapping(let mapping):
            return mapping.reduce((mappings: 1, sequences: 0, scalars: 0)) { result, pair in
                let valueCounts = valueCounts(in: pair.value)
                return (
                    mappings: result.mappings + valueCounts.mappings,
                    sequences: result.sequences + valueCounts.sequences,
                    scalars: result.scalars + valueCounts.scalars
                )
            }
        case .sequence(let sequence):
            return sequence.reduce((mappings: 0, sequences: 1, scalars: 0)) { result, item in
                let itemCounts = valueCounts(in: item)
                return (
                    mappings: result.mappings + itemCounts.mappings,
                    sequences: result.sequences + itemCounts.sequences,
                    scalars: result.scalars + itemCounts.scalars
                )
            }
        case .scalar:
            return (mappings: 0, sequences: 0, scalars: 1)
        case .alias:
            return (mappings: 0, sequences: 0, scalars: 0)
        }
    }

    private static func scalarKeyLabel(_ node: Node) -> String? {
        guard case .scalar(let scalar) = node else { return nil }
        return sanitizedLabel(scalar.string)
    }

    private static func previewLabel(for keys: [String]) -> String? {
        guard !keys.isEmpty else { return nil }
        let visibleKeys = keys.prefix(keyPreviewLimit)
        let remainder = keys.count - visibleKeys.count
        return ([visibleKeys.joined(separator: ", ")] + (remainder > 0 ? ["+\(remainder) more"] : []))
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private static func previewLabels(for keys: [String]) -> [String] {
        Array(keys.prefix(keyPreviewLimit))
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

    private static let supportedExtensions: Set<String> = ["yaml", "yml"]
    private static let byteLimit = 64 * 1_024
    private static let keyPreviewLimit = 6
    private static let keyCharacterLimit = 80
}
