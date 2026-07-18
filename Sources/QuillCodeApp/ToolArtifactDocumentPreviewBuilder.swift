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
        if filename == ".env" || filename.hasPrefix(".env.") {
            return "env"
        }
        for compoundExtension in compoundPreviewExtensions {
            if filename.hasSuffix(".\(compoundExtension.suffix)") {
                return compoundExtension.previewExtension
            }
        }
        return ToolArtifactValueClassifier.pathExtension(for: value)
    }

    private static let compoundPreviewExtensions: [(suffix: String, previewExtension: String)] = [
        ("appshot.json", "appshot"),
        ("tar.gz", "tar.gz"),
        ("tar.bz2", "tar.bz2"),
        ("tar.xz", "tar.xz"),
        ("tar.zst", "tar.zst")
    ]

    private static let documentKindsByExtension: [String: ToolArtifactDocumentKind] = [
        "appshot": .appshot,
        "pdf": .pdf,
        "markdown": .markdown,
        "md": .markdown,
        "json": .data,
        "jsonl": .data,
        "ndjson": .data,
        "cfg": .data,
        "conf": .data,
        "env": .data,
        "ini": .data,
        "toml": .data,
        "yaml": .data,
        "yml": .data,
        "xml": .data,
        "plist": .data,
        "doc": .document,
        "docx": .document,
        "odt": .document,
        "pages": .document,
        "rtf": .document,
        "numbers": .spreadsheet,
        "csv": .spreadsheet,
        "ods": .spreadsheet,
        "tsv": .spreadsheet,
        "xls": .spreadsheet,
        "xlsx": .spreadsheet,
        "key": .presentation,
        "odp": .presentation,
        "ppt": .presentation,
        "pptx": .presentation,
        "aac": .audio,
        "aif": .audio,
        "aiff": .audio,
        "flac": .audio,
        "m4a": .audio,
        "mp3": .audio,
        "ogg": .audio,
        "opus": .audio,
        "wav": .audio,
        "webm": .video,
        "m4v": .video,
        "mov": .video,
        "mp4": .video,
        "7z": .archive,
        "bz2": .archive,
        "gz": .archive,
        "rar": .archive,
        "tar": .archive,
        "tar.bz2": .archive,
        "tar.gz": .archive,
        "tar.xz": .archive,
        "tar.zst": .archive,
        "tbz": .archive,
        "tbz2": .archive,
        "tgz": .archive,
        "tzst": .archive,
        "txz": .archive,
        "xz": .archive,
        "zip": .archive,
        "zst": .archive
    ]
}
