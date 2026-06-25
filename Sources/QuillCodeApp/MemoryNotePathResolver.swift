import Foundation
import QuillCodeCore

enum MemoryNotePathResolver {
    static func globalMemoryFileURL(for note: MemoryNote, in root: URL) -> URL? {
        let prefix = "memories/"
        guard note.scope == .global,
              note.relativePath.hasPrefix(prefix)
        else {
            return nil
        }
        let filename = String(note.relativePath.dropFirst(prefix.count))
        guard isSingleFilename(filename) else {
            return nil
        }
        let fileURL = root
            .appendingPathComponent(filename)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard fileURL.deletingLastPathComponent().path == root.path else {
            return nil
        }
        return fileURL
    }

    static func projectMemoryDirectory(in root: URL, relativeDirectory: String) -> URL? {
        guard isSafeRelativeDirectory(relativeDirectory) else { return nil }
        let directory = root
            .appendingPathComponent(relativeDirectory)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard directory.path.hasPrefix(root.path + "/") else { return nil }
        return directory
    }

    static func projectMemoryFileURL(
        for note: MemoryNote,
        root: URL,
        directory: URL,
        relativeDirectory: String
    ) -> URL? {
        let prefix = "\(relativeDirectory)/"
        guard note.scope == .project,
              note.relativePath.hasPrefix(prefix)
        else {
            return nil
        }
        let filename = String(note.relativePath.dropFirst(prefix.count))
        guard isSingleFilename(filename) else {
            return nil
        }
        let fileURL = directory
            .appendingPathComponent(filename)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard fileURL.deletingLastPathComponent().path == directory.path,
              fileURL.path.hasPrefix(root.path + "/")
        else {
            return nil
        }
        return fileURL
    }

    private static func isSafeRelativeDirectory(_ relativeDirectory: String) -> Bool {
        guard !relativeDirectory.isEmpty,
              !relativeDirectory.hasPrefix("/"),
              !relativeDirectory.contains("..")
        else {
            return false
        }
        return true
    }

    private static func isSingleFilename(_ filename: String) -> Bool {
        !filename.isEmpty && !filename.contains("/")
    }
}
