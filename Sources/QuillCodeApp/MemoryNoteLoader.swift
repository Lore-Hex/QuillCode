import Foundation
import QuillCodeCore

public enum MemoryNoteWriteError: Error, Equatable, LocalizedError {
    case empty
    case tooLarge(actual: Int, maximum: Int)
    case sensitiveContent
    case unavailable
    case writeFailed

    public var errorDescription: String? {
        switch self {
        case .empty:
            return "Nothing to remember. Use `/remember a durable preference or fact`."
        case .tooLarge(let actual, let maximum):
            return "Memory is too large (\(actual) bytes). Keep explicit memories under \(maximum) bytes."
        case .sensitiveContent:
            return "Memory was not saved because it looks like it contains a credential, token, password, or private key."
        case .unavailable:
            return "Memory saving is unavailable in this runtime."
        case .writeFailed:
            return "Memory could not be written."
        }
    }
}

public enum MemoryNoteDeleteError: Error, Equatable, LocalizedError {
    case notFound
    case deleteFailed

    public var errorDescription: String? {
        switch self {
        case .notFound:
            return "Memory was not found. It may already have been removed."
        case .deleteFailed:
            return "Memory could not be deleted."
        }
    }
}

public enum MemoryNoteUpdateError: Error, Equatable, LocalizedError {
    case notFound
    case empty
    case tooLarge(actual: Int, maximum: Int)
    case sensitiveContent
    case updateFailed

    public var errorDescription: String? {
        switch self {
        case .notFound:
            return "Memory was not found. It may already have been removed."
        case .empty:
            return "Memory cannot be empty."
        case .tooLarge(let actual, let maximum):
            return "Memory is too large (\(actual) bytes). Keep explicit memories under \(maximum) bytes."
        case .sensitiveContent:
            return "Memory was not updated because it looks like it contains a credential, token, password, or private key."
        case .updateFailed:
            return "Memory could not be updated."
        }
    }
}

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
        guard let directory = MemoryNotePathResolver.projectMemoryDirectory(in: root, relativeDirectory: relativeDirectory) else { return [] }
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

    public static func saveGlobal(
        content rawContent: String,
        to directory: URL,
        now: Date = Date(),
        maxBytes: Int = maxFileBytes
    ) throws -> MemoryNote {
        let content = try MemoryNoteContentPolicy.validatedWriteContent(rawContent, maxBytes: maxBytes)

        let root = directory.standardizedFileURL.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let title = MemoryNoteContentPolicy.title(
            from: MemoryNoteContentPolicy.titleBase(from: content)
        )
        let filename = MemoryNoteContentPolicy.availableFilename(
            in: root,
            now: now,
            title: title
        )
        let fileURL = root.appendingPathComponent(filename)
        try content.appending("\n").write(to: fileURL, atomically: true, encoding: .utf8)
        guard let note = loadFile(
            root: root,
            fileURL: fileURL,
            scope: .global,
            displayPrefix: "memories",
            maxBytes: maxBytes
        ) else {
            throw MemoryNoteWriteError.writeFailed
        }
        return note
    }

    public static func updateGlobal(
        id: String,
        content rawContent: String,
        in directory: URL,
        maxBytes: Int = maxFileBytes
    ) throws -> MemoryNote {
        let root = directory.standardizedFileURL.resolvingSymlinksInPath()
        guard let existing = loadGlobal(from: root).first(where: { $0.id == id && $0.scope == .global }),
              let fileURL = MemoryNotePathResolver.globalMemoryFileURL(for: existing, in: root)
        else {
            throw MemoryNoteUpdateError.notFound
        }

        let content = try validatedUpdateContent(rawContent, maxBytes: maxBytes)
        do {
            try content.appending("\n").write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            throw MemoryNoteUpdateError.updateFailed
        }
        guard let updated = loadFile(
            root: root,
            fileURL: fileURL,
            scope: .global,
            displayPrefix: "memories",
            maxBytes: maxBytes
        ) else {
            throw MemoryNoteUpdateError.updateFailed
        }
        return updated
    }

    public static func updateProject(
        id: String,
        content rawContent: String,
        in projectRoot: URL,
        relativeDirectory: String = projectRelativeDirectory,
        maxBytes: Int = maxFileBytes
    ) throws -> MemoryNote {
        let root = projectRoot.standardizedFileURL.resolvingSymlinksInPath()
        guard let directory = MemoryNotePathResolver.projectMemoryDirectory(in: root, relativeDirectory: relativeDirectory),
              let existing = loadProject(from: root, relativeDirectory: relativeDirectory).first(where: { $0.id == id && $0.scope == .project }),
              let fileURL = MemoryNotePathResolver.projectMemoryFileURL(for: existing, root: root, directory: directory, relativeDirectory: relativeDirectory)
        else {
            throw MemoryNoteUpdateError.notFound
        }

        let content = try validatedUpdateContent(rawContent, maxBytes: maxBytes)
        do {
            try content.appending("\n").write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            throw MemoryNoteUpdateError.updateFailed
        }
        guard let updated = loadFile(
            root: root,
            fileURL: fileURL,
            scope: .project,
            displayPrefix: relativeDirectory,
            maxBytes: maxBytes
        ) else {
            throw MemoryNoteUpdateError.updateFailed
        }
        return updated
    }

    public static func deleteGlobal(
        id: String,
        from directory: URL
    ) throws -> MemoryNote {
        let root = directory.standardizedFileURL.resolvingSymlinksInPath()
        guard let note = loadGlobal(from: root).first(where: { $0.id == id && $0.scope == .global }) else {
            throw MemoryNoteDeleteError.notFound
        }
        guard let fileURL = MemoryNotePathResolver.globalMemoryFileURL(for: note, in: root) else {
            throw MemoryNoteDeleteError.notFound
        }

        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            throw MemoryNoteDeleteError.deleteFailed
        }
        return note
    }

    public static func deleteProject(
        id: String,
        from projectRoot: URL,
        relativeDirectory: String = projectRelativeDirectory
    ) throws -> MemoryNote {
        let root = projectRoot.standardizedFileURL.resolvingSymlinksInPath()
        guard let directory = MemoryNotePathResolver.projectMemoryDirectory(in: root, relativeDirectory: relativeDirectory),
              let note = loadProject(from: root, relativeDirectory: relativeDirectory).first(where: { $0.id == id && $0.scope == .project }),
              let fileURL = MemoryNotePathResolver.projectMemoryFileURL(for: note, root: root, directory: directory, relativeDirectory: relativeDirectory)
        else {
            throw MemoryNoteDeleteError.notFound
        }

        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            throw MemoryNoteDeleteError.deleteFailed
        }
        return note
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

    static func validatedUpdateContent(_ rawContent: String, maxBytes: Int = maxFileBytes) throws -> String {
        try MemoryNoteContentPolicy.validatedUpdateContent(rawContent, maxBytes: maxBytes)
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
            title: MemoryNoteContentPolicy.title(from: resolved.deletingPathExtension().lastPathComponent),
            content: content,
            relativePath: relativePath,
            byteCount: min(data.count, maxBytes),
            wasTruncated: wasTruncated
        )
    }

}
