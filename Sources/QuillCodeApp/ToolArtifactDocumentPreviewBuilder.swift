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
        if filename == "lcov.info" {
            return "lcov"
        }
        if filename == "cover.out" || filename == "coverage.out" {
            return "gocover"
        }
        if filename == "go.sum" {
            return "gosum"
        }
        if filename == "requirements.txt" || (filename.hasPrefix("requirements-") && filename.hasSuffix(".txt")) {
            return "requirements"
        }
        if filename == "poetry.lock" {
            return "poetry-lock"
        }
        if filename == "pipfile.lock" {
            return "pipfile-lock"
        }
        if filename == "package.resolved" {
            return "spm"
        }
        if filename == "composer.lock" {
            return "composer-lock"
        }
        if filename == "pnpm-lock.yaml" {
            return "pnpm-lock"
        }
        if filename == "yarn.lock" {
            return "yarn-lock"
        }
        if filename == "cargo.lock" {
            return "cargo-lock"
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
        ("sarif.json", "sarif"),
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
        "mdx": .markdown,
        "json": .data,
        "jsonl": .data,
        "lcov": .data,
        "gocover": .data,
        "gosum": .data,
        "requirements": .data,
        "poetry-lock": .data,
        "pipfile-lock": .data,
        "ndjson": .data,
        "sarif": .data,
        "cfg": .data,
        "conf": .data,
        "composer-lock": .data,
        "pnpm-lock": .data,
        "yarn-lock": .data,
        "cargo-lock": .data,
        "bin": .data,
        "db": .data,
        "diff": .data,
        "dll": .data,
        "dylib": .data,
        "env": .data,
        "exe": .data,
        "har": .data,
        "otf": .data,
        "ini": .data,
        "o": .data,
        "patch": .data,
        "sqlite": .data,
        "sqlite3": .data,
        "spm": .data,
        "so": .data,
        "tap": .data,
        "ttc": .data,
        "ttf": .data,
        "toml": .data,
        "trx": .data,
        "wasm": .data,
        "woff": .data,
        "woff2": .data,
        "yaml": .data,
        "yml": .data,
        "xml": .data,
        "plist": .data,
        "doc": .document,
        "docx": .document,
        "htm": .document,
        "html": .document,
        "ipynb": .document,
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
        "apk": .archive,
        "bz2": .archive,
        "ear": .archive,
        "epub": .archive,
        "gz": .archive,
        "ipa": .archive,
        "jar": .archive,
        "nupkg": .archive,
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
        "vsix": .archive,
        "war": .archive,
        "whl": .archive,
        "xz": .archive,
        "xpi": .archive,
        "zip": .archive,
        "zst": .archive
    ]
}
