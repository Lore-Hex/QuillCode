import Foundation

enum ToolArtifactTextPreviewBuilder {
    static func textPreview(for value: String) -> String? {
        let artifact = ToolArtifactState(value: value)
        guard artifact.kind == .file,
              !artifact.isImagePreview,
              artifact.documentPreview?.kind != .appshot,
              artifact.documentPreview?.extensionLabel.lowercased() != "env",
              artifact.tablePreview == nil
        else { return nil }
        guard let fileURL = localArtifactFileURL(for: value) else { return nil }
        guard isTextPreviewCandidate(fileURL) else { return nil }

        do {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true else { return nil }

            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }

            guard let data = try handle.read(upToCount: byteLimit + 1),
                  !data.isEmpty
            else { return nil }

            var wasTruncated = data.count > byteLimit
            let previewData = Data(data.prefix(byteLimit))
            guard !previewData.contains(0),
                  var text = String(data: previewData, encoding: .utf8)
            else { return nil }

            text = text.replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            if lines.count > lineLimit {
                wasTruncated = true
                text = lines.prefix(lineLimit).joined(separator: "\n")
            }
            if wasTruncated {
                if !text.hasSuffix("\n") {
                    text += "\n"
                }
                text += "..."
            }
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
        } catch {
            return nil
        }
    }

    private static func localArtifactFileURL(for value: String) -> URL? {
        if value.hasPrefix("/") {
            return URL(fileURLWithPath: value)
        }
        guard let url = URL(string: value),
              url.scheme?.lowercased() == "file"
        else { return nil }
        return url
    }

    private static func isTextPreviewCandidate(_ url: URL) -> Bool {
        let filename = url.lastPathComponent.lowercased()
        if filenames.contains(filename) {
            return true
        }
        let pathExtension = url.pathExtension.lowercased()
        return extensions.contains(pathExtension)
    }

    private static let byteLimit = 6 * 1024
    private static let lineLimit = 80
    private static let filenames: Set<String> = [
        ".gitignore",
        "dockerfile",
        "gemfile",
        "license",
        "makefile",
        "podfile",
        "readme"
    ]
    private static let extensions: Set<String> = [
        "c",
        "cc",
        "conf",
        "cpp",
        "css",
        "csv",
        "go",
        "h",
        "hpp",
        "html",
        "java",
        "js",
        "json",
        "jsonl",
        "jsx",
        "kt",
        "log",
        "m",
        "md",
        "mm",
        "ndjson",
        "py",
        "rb",
        "rs",
        "sh",
        "sql",
        "swift",
        "toml",
        "ts",
        "tsx",
        "txt",
        "xml",
        "yaml",
        "yml"
    ]
}
