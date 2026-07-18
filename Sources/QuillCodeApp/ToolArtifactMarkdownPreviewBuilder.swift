import Foundation

enum ToolArtifactMarkdownPreviewBuilder {
    static func markdownPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactMarkdownPreview? {
        guard kind == .file,
              ToolArtifactDocumentPreviewBuilder.documentPreview(for: value, kind: kind)?.kind == .markdown,
              let fileURL = localArtifactFileURL(for: value)
        else {
            return nil
        }

        do {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard resourceValues.isRegularFile == true else { return nil }
            let fileSize = max(resourceValues.fileSize ?? 0, 0)
            let data = try prefixData(from: fileURL, fileSize: fileSize)
            guard !data.contains(0),
                  let text = String(data: data, encoding: .utf8)
            else {
                return nil
            }

            let preview = ToolArtifactMarkdownPreview(
                title: firstHeading(in: text),
                headingCount: headingCount(in: text),
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

    private static func firstHeading(in text: String) -> String? {
        for line in normalizedLines(text) {
            guard let heading = headingTitle(in: line) else { continue }
            return heading
        }
        return nil
    }

    private static func headingCount(in text: String) -> Int {
        normalizedLines(text).reduce(0) { count, line in
            headingTitle(in: line) == nil ? count : count + 1
        }
    }

    private static func headingTitle(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }
        let markerCount = trimmed.prefix { $0 == "#" }.count
        guard (1...6).contains(markerCount),
              trimmed.dropFirst(markerCount).first == " "
        else {
            return nil
        }
        let rawTitle = String(trimmed.dropFirst(markerCount))
        let title = rawTitle
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: #"\s+#*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? nil : String(title.prefix(titleCharacterLimit))
    }

    private static func normalizedLines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
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
