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
        return MemoryNoteFileReader.load(
            root: root,
            directory: root,
            supportedExtensions: supportedExtensions,
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
        guard let directory = MemoryNotePathResolver.projectMemoryDirectory(
            in: root,
            relativeDirectory: relativeDirectory
        ) else { return [] }
        return MemoryNoteFileReader.load(
            root: root,
            directory: directory,
            supportedExtensions: supportedExtensions,
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
        guard let note = MemoryNoteFileReader.loadFile(
            root: root,
            fileURL: fileURL,
            supportedExtensions: supportedExtensions,
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
        return try updateNote(
            in: globalLocation(id: id, root: root, notFoundError: MemoryNoteUpdateError.notFound),
            content: rawContent,
            maxBytes: maxBytes
        )
    }

    public static func updateProject(
        id: String,
        content rawContent: String,
        in projectRoot: URL,
        relativeDirectory: String = projectRelativeDirectory,
        maxBytes: Int = maxFileBytes
    ) throws -> MemoryNote {
        let root = projectRoot.standardizedFileURL.resolvingSymlinksInPath()
        return try updateNote(
            in: projectLocation(
                id: id,
                root: root,
                relativeDirectory: relativeDirectory,
                notFoundError: MemoryNoteUpdateError.notFound
            ),
            content: rawContent,
            maxBytes: maxBytes
        )
    }

    public static func deleteGlobal(
        id: String,
        from directory: URL
    ) throws -> MemoryNote {
        let root = directory.standardizedFileURL.resolvingSymlinksInPath()
        return try deleteNote(in: globalLocation(id: id, root: root, notFoundError: MemoryNoteDeleteError.notFound))
    }

    public static func deleteProject(
        id: String,
        from projectRoot: URL,
        relativeDirectory: String = projectRelativeDirectory
    ) throws -> MemoryNote {
        let root = projectRoot.standardizedFileURL.resolvingSymlinksInPath()
        return try deleteNote(
            in: projectLocation(
                id: id,
                root: root,
                relativeDirectory: relativeDirectory,
                notFoundError: MemoryNoteDeleteError.notFound
            )
        )
    }

    private static func updateNote(
        in location: MemoryNoteFileLocation,
        content rawContent: String,
        maxBytes: Int
    ) throws -> MemoryNote {
        let content = try validatedUpdateContent(rawContent, maxBytes: maxBytes)
        do {
            try content.appending("\n").write(to: location.fileURL, atomically: true, encoding: .utf8)
        } catch {
            throw MemoryNoteUpdateError.updateFailed
        }
        guard let updated = MemoryNoteFileReader.loadFile(
            root: location.root,
            fileURL: location.fileURL,
            supportedExtensions: supportedExtensions,
            scope: location.note.scope,
            displayPrefix: location.displayPrefix,
            maxBytes: maxBytes
        ) else {
            throw MemoryNoteUpdateError.updateFailed
        }
        return updated
    }

    private static func deleteNote(in location: MemoryNoteFileLocation) throws -> MemoryNote {
        do {
            try FileManager.default.removeItem(at: location.fileURL)
        } catch {
            throw MemoryNoteDeleteError.deleteFailed
        }
        return location.note
    }

    private static func globalLocation(
        id: String,
        root: URL,
        notFoundError: Error
    ) throws -> MemoryNoteFileLocation {
        guard let note = loadGlobal(from: root).first(where: { $0.id == id && $0.scope == .global }) else {
            throw notFoundError
        }
        guard let fileURL = MemoryNotePathResolver.globalMemoryFileURL(for: note, in: root) else {
            throw notFoundError
        }
        return MemoryNoteFileLocation(
            note: note,
            root: root,
            fileURL: fileURL,
            displayPrefix: "memories"
        )
    }

    private static func projectLocation(
        id: String,
        root: URL,
        relativeDirectory: String,
        notFoundError: Error
    ) throws -> MemoryNoteFileLocation {
        guard let directory = MemoryNotePathResolver.projectMemoryDirectory(
                  in: root,
                  relativeDirectory: relativeDirectory
              ),
              let note = loadProject(from: root, relativeDirectory: relativeDirectory)
                  .first(where: { $0.id == id && $0.scope == .project }),
              let fileURL = MemoryNotePathResolver.projectMemoryFileURL(
                  for: note,
                  root: root,
                  directory: directory,
                  relativeDirectory: relativeDirectory
        )
        else {
            throw notFoundError
        }
        return MemoryNoteFileLocation(
            note: note,
            root: root,
            fileURL: fileURL,
            displayPrefix: relativeDirectory
        )
    }

    static func validatedUpdateContent(_ rawContent: String, maxBytes: Int = maxFileBytes) throws -> String {
        try MemoryNoteContentPolicy.validatedUpdateContent(rawContent, maxBytes: maxBytes)
    }

}

private struct MemoryNoteFileLocation {
    var note: MemoryNote
    var root: URL
    var fileURL: URL
    var displayPrefix: String
}
