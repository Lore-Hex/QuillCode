import Foundation

enum ToolArtifactPDFPreviewBuilder {
    static func pdfPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactPDFPreview? {
        guard kind == .file,
              ToolArtifactDocumentPreviewBuilder.documentPreview(for: value, kind: kind)?.kind == .pdf,
              let fileURL = localArtifactFileURL(for: value)
        else {
            return nil
        }

        do {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard resourceValues.isRegularFile == true else { return nil }

            let fileSize = max(resourceValues.fileSize ?? 0, 0)
            let data = try prefixData(from: fileURL, fileSize: fileSize)
            let text = String(data: data, encoding: .isoLatin1) ?? ""
            let isTruncated = fileSize > byteLimit
            let pageCount = isTruncated ? nil : parsedPageCount(from: text)
            let preview = ToolArtifactPDFPreview(
                title: parsedTitle(from: text),
                versionLabel: parsedVersion(from: text),
                pageCount: pageCount,
                byteSizeLabel: byteSizeLabel(for: fileSize),
                isTruncated: isTruncated
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

    private static func parsedVersion(from text: String) -> String? {
        guard let match = firstMatch(pattern: #"%PDF-(\d+\.\d+)"#, in: text) else {
            return nil
        }
        return "PDF \(capture(1, in: text, match: match))"
    }

    private static func parsedTitle(from text: String) -> String? {
        guard let match = firstMatch(pattern: #"/Title\s*\((.{1,240}?)\)"#, in: text, options: [.dotMatchesLineSeparators]) else {
            return nil
        }
        let title = capture(1, in: text, match: match)
            .replacingOccurrences(of: #"\\\("#, with: "(")
            .replacingOccurrences(of: #"\\\)"#, with: ")")
            .replacingOccurrences(of: #"\\n"#, with: " ")
            .replacingOccurrences(of: #"\\r"#, with: " ")
            .replacingOccurrences(of: #"\\t"#, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    private static func parsedPageCount(from text: String) -> Int? {
        let pageTypeCount = matchCount(pattern: #"/Type\s*/Page(?![A-Za-z])"#, in: text)
        if pageTypeCount > 0 {
            return pageTypeCount
        }
        let counts = matches(pattern: #"/Count\s+(\d{1,6})"#, in: text)
            .compactMap { Int(capture(1, in: text, match: $0)) }
            .filter { $0 > 0 }
        return counts.max()
    }

    private static func byteSizeLabel(for byteCount: Int) -> String? {
        guard byteCount > 0 else { return nil }
        if byteCount == 1 { return "1 byte" }
        if byteCount < 1_024 { return "\(byteCount) bytes" }
        let kilobytes = Double(byteCount) / 1_024.0
        if kilobytes < 1_024 {
            return "\(formatted(kilobytes)) KB"
        }
        let megabytes = kilobytes / 1_024.0
        return "\(formatted(megabytes)) MB"
    }

    private static func formatted(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded.rounded() == rounded {
            return "\(Int(rounded))"
        }
        return String(format: "%.1f", rounded)
    }

    private static func firstMatch(
        pattern: String,
        in text: String,
        options: NSRegularExpression.Options = []
    ) -> NSTextCheckingResult? {
        matches(pattern: pattern, in: text, options: options).first
    }

    private static func matchCount(pattern: String, in text: String) -> Int {
        matches(pattern: pattern, in: text).count
    }

    private static func matches(
        pattern: String,
        in text: String,
        options: NSRegularExpression.Options = []
    ) -> [NSTextCheckingResult] {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else {
            return []
        }
        return expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
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

    private static let byteLimit = 512 * 1_024
}
