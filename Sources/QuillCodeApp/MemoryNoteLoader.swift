import Foundation
import QuillCodeCore

public enum MemoryNoteLoader {
    public static let projectRelativeDirectory = ".quillcode/memories"
    public static let supportedExtensions: Set<String> = ["md", "txt", "json"]
    public static let maxNotes = 32
    public static let maxFileBytes = 12_000
    public static let maxTotalBytes = 96_000

    public static func loadGlobal(
        from directory: URL,
        maxNotes: Int = maxNotes,
        maxFileBytes: Int = maxFileBytes,
        maxTotalBytes: Int = maxTotalBytes
    ) -> [MemoryNote] {
        let root = directory.standardizedFileURL.resolvingSymlinksInPath()
        return load(
            root: root,
            directory: root,
            scope: .global,
            displayPrefix: "memories",
            maxNotes: maxNotes,
            maxFileBytes: maxFileBytes,
            maxTotalBytes: maxTotalBytes
        )
    }

    public static func loadProject(
        from projectRoot: URL,
        relativeDirectory: String = projectRelativeDirectory,
        maxNotes: Int = maxNotes,
        maxFileBytes: Int = maxFileBytes,
        maxTotalBytes: Int = maxTotalBytes
    ) -> [MemoryNote] {
        let root = projectRoot.standardizedFileURL.resolvingSymlinksInPath()
        guard !relativeDirectory.contains("..") else { return [] }
        let directory = root
            .appendingPathComponent(relativeDirectory)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard directory.path.hasPrefix(root.path + "/") else { return [] }
        return load(
            root: root,
            directory: directory,
            scope: .project,
            displayPrefix: relativeDirectory,
            maxNotes: maxNotes,
            maxFileBytes: maxFileBytes,
            maxTotalBytes: maxTotalBytes
        )
    }

    private static func load(
        root: URL,
        directory: URL,
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

    private static func loadFile(
        root: URL,
        fileURL: URL,
        scope: MemoryScope,
        displayPrefix: String,
        maxBytes: Int
    ) -> MemoryNote? {
        guard maxBytes > 0,
              supportedExtensions.contains(fileURL.pathExtension.lowercased())
        else {
            return nil
        }

        let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values?.isRegularFile == true,
              values?.isSymbolicLink != true
        else {
            return nil
        }

        let resolved = fileURL.standardizedFileURL.resolvingSymlinksInPath()
        guard resolved.path.hasPrefix(root.path + "/") || resolved.deletingLastPathComponent().path == root.path else {
            return nil
        }

        guard let handle = try? FileHandle(forReadingFrom: resolved) else { return nil }
        defer { try? handle.close() }

        let data = handle.readData(ofLength: maxBytes + 1)
        let wasTruncated = data.count > maxBytes
        let boundedData = wasTruncated ? data.prefix(maxBytes) : data[...]
        guard var content = String(data: Data(boundedData), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty
        else {
            return nil
        }
        if wasTruncated {
            content += "\n\n[QuillCode truncated this memory file at \(maxBytes) bytes.]"
        }

        let relativePath = "\(displayPrefix)/\(resolved.lastPathComponent)"
        return MemoryNote(
            id: "\(scope.rawValue):\(relativePath)",
            scope: scope,
            title: title(from: resolved.deletingPathExtension().lastPathComponent),
            content: content,
            relativePath: relativePath,
            byteCount: min(data.count, maxBytes),
            wasTruncated: wasTruncated
        )
    }

    private static func title(from baseName: String) -> String {
        let words = baseName
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .map(String.init)
        guard !words.isEmpty else { return baseName }
        return words
            .map { word in
                guard let first = word.first else { return word }
                return first.uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }
}
