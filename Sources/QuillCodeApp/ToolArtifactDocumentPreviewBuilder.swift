import Foundation

enum ToolArtifactDocumentPreviewBuilder {
    static func documentPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactDocumentPreview? {
        guard kind == .file || kind == .url,
              !ToolArtifactImagePreviewBuilder.isImagePreview(for: value, kind: kind)
        else {
            return nil
        }
        let fileExtension = previewExtension(for: value)
        guard let documentKind = documentKindsByExtension[fileExtension] else {
            return nil
        }
        return ToolArtifactDocumentPreview(
            kind: documentKind,
            extensionLabel: fileExtension.uppercased(),
            detail: ToolArtifactValueClassifier.detail(for: value, kind: kind)
        )
    }

    private static func previewExtension(for value: String) -> String {
        let filename: String
        if let url = URL(string: value), url.scheme != nil {
            filename = url.lastPathComponent.lowercased()
        } else {
            filename = URL(fileURLWithPath: value).lastPathComponent.lowercased()
        }
        if filename.hasSuffix(".appshot.json") {
            return "appshot"
        }
        return ToolArtifactValueClassifier.pathExtension(for: value)
    }

    private static let documentKindsByExtension: [String: ToolArtifactDocumentKind] = [
        "appshot": .appshot,
        "pdf": .pdf,
        "doc": .document,
        "docx": .document,
        "odt": .document,
        "pages": .document,
        "rtf": .document,
        "numbers": .spreadsheet,
        "ods": .spreadsheet,
        "xls": .spreadsheet,
        "xlsx": .spreadsheet,
        "key": .presentation,
        "odp": .presentation,
        "ppt": .presentation,
        "pptx": .presentation
    ]
}
