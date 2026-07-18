import Foundation

enum ToolArtifactHTMLPreviewBuilder {
    static func htmlPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactHTMLPreview? {
        guard kind == .file,
              let documentPreview = ToolArtifactDocumentPreviewBuilder.documentPreview(for: value, kind: kind),
              documentPreview.kind == .document,
              ["html", "htm"].contains(documentPreview.extensionLabel.lowercased()),
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
                  let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
                  looksLikeHTML(html)
            else {
                return nil
            }

            let preview = ToolArtifactHTMLPreview(
                title: firstHTMLCapture(in: html, pattern: #"<title[^>]*>(.*?)</title>"#),
                heading: firstHTMLCapture(in: html, pattern: #"<h[1-2][^>]*>(.*?)</h[1-2]>"#),
                linkCount: htmlTagCount("a", in: html),
                scriptCount: htmlTagCount("script", in: html),
                styleCount: htmlTagCount("style", in: html),
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

    private static func looksLikeHTML(_ html: String) -> Bool {
        let prefix = html.prefix(512).lowercased()
        return prefix.contains("<!doctype html")
            || prefix.contains("<html")
            || prefix.contains("<head")
            || prefix.contains("<body")
    }

    private static func firstHTMLCapture(in html: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: html)
        else {
            return nil
        }
        let text = cleanHTMLText(String(html[captureRange]))
        return text.isEmpty ? nil : String(text.prefix(textCharacterLimit))
    }

    private static func htmlTagCount(_ tag: String, in html: String) -> Int {
        guard let regex = try? NSRegularExpression(
            pattern: #"<\#(tag)(?:\s|>|/)"#,
            options: [.caseInsensitive]
        ) else {
            return 0
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.numberOfMatches(in: html, range: range)
    }

    private static func cleanHTMLText(_ raw: String) -> String {
        raw.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"&nbsp;"#, with: " ", options: .caseInsensitive)
            .replacingOccurrences(of: #"&amp;"#, with: "&", options: .caseInsensitive)
            .replacingOccurrences(of: #"&lt;"#, with: "<", options: .caseInsensitive)
            .replacingOccurrences(of: #"&gt;"#, with: ">", options: .caseInsensitive)
            .replacingOccurrences(of: #"&quot;"#, with: "\"", options: .caseInsensitive)
            .replacingOccurrences(of: #"&#39;"#, with: "'", options: .caseInsensitive)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
    private static let textCharacterLimit = 160
}
