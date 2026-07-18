import Foundation

enum ToolArtifactDiffPreviewBuilder {
    static func diffPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactDiffPreview? {
        guard kind == .file,
              let documentPreview = ToolArtifactDocumentPreviewBuilder.documentPreview(for: value, kind: kind),
              documentPreview.kind == .data,
              ["diff", "patch"].contains(documentPreview.extensionLabel.lowercased()),
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
                  looksLikeDiff(text)
            else {
                return nil
            }

            let preview = parseDiff(text, fileSize: fileSize)
            return preview.hasDisplayContent ? preview : nil
        } catch {
            return nil
        }
    }

    private static func parseDiff(_ text: String, fileSize: Int) -> ToolArtifactDiffPreview {
        var hunkCount = 0
        var additionCount = 0
        var deletionCount = 0
        var changedFiles: [String] = []
        var seenChangedFiles = Set<String>()

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasPrefix("diff --git ") {
                appendChangedFile(gitDiffPath(from: line), to: &changedFiles, seen: &seenChangedFiles)
            } else if line.hasPrefix("+++ ") {
                appendChangedFile(fileHeaderPath(from: line), to: &changedFiles, seen: &seenChangedFiles)
            } else if line.hasPrefix("@@") {
                hunkCount += 1
            } else if line.hasPrefix("+"), !line.hasPrefix("+++") {
                additionCount += 1
            } else if line.hasPrefix("-"), !line.hasPrefix("---") {
                deletionCount += 1
            }
        }

        return ToolArtifactDiffPreview(
            fileCount: seenChangedFiles.count,
            hunkCount: hunkCount,
            additionCount: additionCount,
            deletionCount: deletionCount,
            changedFileLabels: Array(changedFiles.prefix(changedFileLimit)),
            byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize),
            isTruncated: fileSize > byteLimit
        )
    }

    private static func looksLikeDiff(_ text: String) -> Bool {
        let prefix = text.prefix(4096)
        return prefix.contains("diff --git ")
            || prefix.contains("\n@@ ")
            || prefix.contains("\n--- ")
            || prefix.contains("\n+++ ")
    }

    private static func appendChangedFile(_ path: String?, to changedFiles: inout [String], seen: inout Set<String>) {
        guard let path, !path.isEmpty, path != "/dev/null", seen.insert(path).inserted else { return }
        changedFiles.append(path)
    }

    private static func gitDiffPath(from line: String) -> String? {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 4 else { return nil }
        return normalizedDiffPath(String(parts[3]))
    }

    private static func fileHeaderPath(from line: String) -> String? {
        let payload = line.dropFirst(4).split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false).first
        return payload.map { normalizedDiffPath(String($0)) } ?? nil
    }

    private static func normalizedDiffPath(_ rawPath: String) -> String {
        var path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.hasPrefix("\""), path.hasSuffix("\""), path.count >= 2 {
            path.removeFirst()
            path.removeLast()
        }
        if path.hasPrefix("a/") || path.hasPrefix("b/") {
            path.removeFirst(2)
        }
        return path
    }

    private static func prefixData(from fileURL: URL, fileSize: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        let requestedBytes = max(1, min(max(fileSize, 1), byteLimit))
        return try handle.read(upToCount: requestedBytes) ?? Data()
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

    private static let byteLimit = 128 * 1_024
    private static let changedFileLimit = 8
}
