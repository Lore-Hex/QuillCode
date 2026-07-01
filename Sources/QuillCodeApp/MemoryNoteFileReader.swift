import Foundation
import QuillCodeCore

enum MemoryNoteFileReader {
    static func load(
        root: URL,
        directory: URL,
        supportedExtensions: Set<String>,
        scope: MemoryScope,
        displayPrefix: String,
        maxNotes: Int,
        maxFileBytes: Int,
        maxTotalBytes: Int
    ) -> [MemoryNote] {
        guard maxNotes > 0, maxFileBytes > 0, maxTotalBytes > 0 else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var totalBytes = 0
        var notes: [MemoryNote] = []
        for fileURL in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard notes.count < maxNotes, totalBytes < maxTotalBytes else { break }
            let remainingBytes = maxTotalBytes - totalBytes
            guard let note = loadFile(
                root: root,
                fileURL: fileURL,
                supportedExtensions: supportedExtensions,
                scope: scope,
                displayPrefix: displayPrefix,
                maxBytes: min(maxFileBytes, remainingBytes)
            ) else {
                continue
            }
            totalBytes += note.byteCount
            notes.append(note)
        }
        return notes
    }

    static func loadFile(
        root: URL,
        fileURL: URL,
        supportedExtensions: Set<String>,
        scope: MemoryScope,
        displayPrefix: String,
        maxBytes: Int
    ) -> MemoryNote? {
        guard maxBytes > 0,
              supportedExtensions.contains(fileURL.pathExtension.lowercased())
        else {
            return nil
        }
        guard isReadableMemoryFile(fileURL, root: root) else {
            return nil
        }
        guard let content = boundedUTF8Content(from: fileURL, maxBytes: maxBytes) else {
            return nil
        }
        return MemoryNote(
            id: "\(scope.rawValue):\(displayPrefix)/\(fileURL.lastPathComponent)",
            scope: scope,
            title: MemoryNoteContentPolicy.title(from: fileURL.deletingPathExtension().lastPathComponent),
            content: content.text,
            relativePath: "\(displayPrefix)/\(fileURL.lastPathComponent)",
            byteCount: content.byteCount,
            wasTruncated: content.wasTruncated
        )
    }

    private static func isReadableMemoryFile(_ fileURL: URL, root: URL) -> Bool {
        let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values?.isRegularFile == true, values?.isSymbolicLink != true else {
            return false
        }
        let resolved = fileURL.standardizedFileURL.resolvingSymlinksInPath()
        return resolved.path.hasPrefix(root.path + "/") || resolved.deletingLastPathComponent().path == root.path
    }

    private static func boundedUTF8Content(
        from fileURL: URL,
        maxBytes: Int
    ) -> MemoryNoteBoundedContent? {
        let resolved = fileURL.standardizedFileURL.resolvingSymlinksInPath()
        guard let handle = try? FileHandle(forReadingFrom: resolved) else { return nil }
        defer { try? handle.close() }

        let data = handle.readData(ofLength: maxBytes + 1)
        let wasTruncated = data.count > maxBytes
        let boundedData = wasTruncated ? data.prefix(maxBytes) : data[...]
        guard var text = String(data: Data(boundedData), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else {
            return nil
        }
        if wasTruncated {
            text += "\n\n[QuillCode truncated this memory file at \(maxBytes) bytes.]"
        }
        return MemoryNoteBoundedContent(
            text: text,
            byteCount: min(data.count, maxBytes),
            wasTruncated: wasTruncated
        )
    }
}

private struct MemoryNoteBoundedContent {
    var text: String
    var byteCount: Int
    var wasTruncated: Bool
}
