enum ToolArtifactImagePreviewBuilder {
    static func isImagePreview(for value: String, kind: ToolArtifactKind) -> Bool {
        if ToolArtifactValueClassifier.isInlineImageData(value) {
            return true
        }
        guard kind == .file || kind == .url else {
            return false
        }
        return imageExtensions.contains(ToolArtifactValueClassifier.pathExtension(for: value))
    }

    static func previewURL(for value: String, kind: ToolArtifactKind) -> String? {
        if ToolArtifactValueClassifier.isInlineImageData(value) {
            return value
        }
        guard isImagePreview(for: value, kind: kind) else {
            return nil
        }
        return ToolArtifactValueClassifier.href(for: value, kind: kind)
    }

    static func imagePreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactImagePreview? {
        guard isImagePreview(for: value, kind: kind) else {
            return nil
        }
        return ToolArtifactImagePreview(
            extensionLabel: imagePreviewExtension(for: value),
            detail: ToolArtifactValueClassifier.detail(for: value, kind: kind),
            dimensionsLabel: ToolArtifactImageMetadataReader.dimensionsLabel(for: value, kind: kind)
        )
    }

    private static func imagePreviewExtension(for value: String) -> String {
        if let subtype = inlineImageSubtype(for: value) {
            return normalizedImageExtension(subtype)
        }
        let fileExtension = ToolArtifactValueClassifier.pathExtension(for: value)
        return fileExtension.isEmpty ? "IMAGE" : normalizedImageExtension(fileExtension)
    }

    private static func inlineImageSubtype(for value: String) -> String? {
        let lowercasedValue = value.lowercased()
        guard lowercasedValue.hasPrefix("data:image/") else {
            return nil
        }
        let afterPrefix = lowercasedValue.dropFirst("data:image/".count)
        let delimiterIndex = afterPrefix.firstIndex { character in
            character == ";" || character == ","
        }
        let subtype = delimiterIndex.map { afterPrefix[..<$0] } ?? afterPrefix[...]
        return subtype.isEmpty ? nil : String(subtype)
    }

    private static func normalizedImageExtension(_ rawExtension: String) -> String {
        let baseExtension = rawExtension
            .lowercased()
            .split(separator: "+", maxSplits: 1)
            .first
            .map(String.init) ?? rawExtension.lowercased()
        switch baseExtension {
        case "jpeg":
            return "JPG"
        case "svg":
            return "SVG"
        case "x-icon":
            return "ICO"
        default:
            return baseExtension.uppercased()
        }
    }

    private static let imageExtensions: Set<String> = [
        "png",
        "jpg",
        "jpeg",
        "gif",
        "webp",
        "heic",
        "tif",
        "tiff",
        "bmp"
    ]
}
