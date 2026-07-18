import Foundation

enum ToolArtifactRTFPreviewBuilder {
    static func rtfPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactRTFPreview? {
        guard kind == .file,
              ToolArtifactDocumentPreviewBuilder.documentPreview(for: value, kind: kind)?.extensionLabel.lowercased() == "rtf",
              let fileURL = localArtifactFileURL(for: value)
        else {
            return nil
        }

        do {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard resourceValues.isRegularFile == true else { return nil }

            let fileSize = max(resourceValues.fileSize ?? 0, 0)
            let data = try prefixData(from: fileURL, fileSize: fileSize)
            guard !data.isEmpty,
                  !data.contains(0),
                  let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
                  text.hasPrefix(#"{\rtf"#)
            else {
                return nil
            }

            let preview = ToolArtifactRTFPreview(
                title: parsedTitle(from: text),
                encodingLabel: parsedEncoding(from: text),
                byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize),
                isTruncated: fileSize > byteLimit
            )
            return preview.hasDisplayContent ? preview : nil
        } catch {
            return nil
        }
    }

    private static func prefixData(from fileURL: URL, fileSize: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        let requestedBytes = max(1, min(max(fileSize, 1), byteLimit))
        return try handle.read(upToCount: requestedBytes) ?? Data()
    }

    private static func parsedTitle(from text: String) -> String? {
        guard let match = firstMatch(pattern: #"\{\\title\s+((?:\\.|[^{}]){1,240})\}"#, in: text) else {
            return nil
        }
        let title = decodeRTFText(capture(1, in: text, match: match))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : String(title.prefix(titleCharacterLimit))
    }

    private static func parsedEncoding(from text: String) -> String? {
        let header = String(text.prefix(256))
        if header.contains(#"\ansi"#) {
            return "ANSI"
        }
        if header.contains(#"\mac"#) {
            return "Mac"
        }
        if header.contains(#"\pca"#) {
            return "PC ANSI"
        }
        if header.contains(#"\pc"#) {
            return "PC"
        }
        return nil
    }

    private static func decodeRTFText(_ text: String) -> String {
        text.replacingOccurrences(of: #"\\\{"#, with: "{")
            .replacingOccurrences(of: #"\\\}"#, with: "}")
            .replacingOccurrences(of: #"\\\\"#, with: "\\")
            .replacingOccurrences(of: #"\\[a-zA-Z]+\d*\s?"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\\'([0-9A-Fa-f]{2})"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func firstMatch(pattern: String, in text: String) -> NSTextCheckingResult? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        return expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func capture(_ index: Int, in text: String, match: NSTextCheckingResult) -> String {
        guard match.numberOfRanges > index,
              let range = Range(match.range(at: index), in: text)
        else {
            return ""
        }
        return String(text[range])
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
    private static let titleCharacterLimit = 160
}
