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
        guard let directory = projectMemoryDirectory(in: root, relativeDirectory: relativeDirectory) else { return [] }
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
        let content = try validatedWriteContent(rawContent, maxBytes: maxBytes)

        let root = directory.standardizedFileURL.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let filename = availableFilename(
            in: root,
            now: now,
            title: title(from: titleBase(from: content))
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
              let fileURL = globalMemoryFileURL(for: existing, in: root)
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
        guard let directory = projectMemoryDirectory(in: root, relativeDirectory: relativeDirectory),
              let existing = loadProject(from: root, relativeDirectory: relativeDirectory).first(where: { $0.id == id && $0.scope == .project }),
              let fileURL = projectMemoryFileURL(for: existing, root: root, directory: directory, relativeDirectory: relativeDirectory)
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
        guard let fileURL = globalMemoryFileURL(for: note, in: root) else {
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

    private static func validatedWriteContent(_ rawContent: String, maxBytes: Int) throws -> String {
        let content = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            throw MemoryNoteWriteError.empty
        }
        let byteCount = Data(content.utf8).count
        guard byteCount <= maxBytes else {
            throw MemoryNoteWriteError.tooLarge(actual: byteCount, maximum: maxBytes)
        }
        guard !looksSensitive(content) else {
            throw MemoryNoteWriteError.sensitiveContent
        }
        return content
    }

    static func validatedUpdateContent(_ rawContent: String, maxBytes: Int = maxFileBytes) throws -> String {
        do {
            return try validatedWriteContent(rawContent, maxBytes: maxBytes)
        } catch MemoryNoteWriteError.empty {
            throw MemoryNoteUpdateError.empty
        } catch MemoryNoteWriteError.tooLarge(let actual, let maximum) {
            throw MemoryNoteUpdateError.tooLarge(actual: actual, maximum: maximum)
        } catch MemoryNoteWriteError.sensitiveContent {
            throw MemoryNoteUpdateError.sensitiveContent
        } catch {
            throw MemoryNoteUpdateError.updateFailed
        }
    }

    private static func globalMemoryFileURL(for note: MemoryNote, in root: URL) -> URL? {
        let prefix = "memories/"
        guard note.scope == .global,
              note.relativePath.hasPrefix(prefix)
        else {
            return nil
        }
        let filename = String(note.relativePath.dropFirst(prefix.count))
        guard !filename.isEmpty, !filename.contains("/") else {
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

    private static func projectMemoryDirectory(in root: URL, relativeDirectory: String) -> URL? {
        guard !relativeDirectory.contains("..") else { return nil }
        let directory = root
            .appendingPathComponent(relativeDirectory)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard directory.path.hasPrefix(root.path + "/") else { return nil }
        return directory
    }

    private static func projectMemoryFileURL(
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
        guard !filename.isEmpty, !filename.contains("/") else {
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

    private static func titleBase(from content: String) -> String {
        let firstLine = content
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? "Memory"
        var trimmed = firstLine
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = trimmed.range(
            of: #"^remember\s+(that\s+)?"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            trimmed.removeSubrange(range)
        }
        trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 60 else { return trimmed.isEmpty ? "Memory" : trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: 60)
        return String(trimmed[..<end])
    }

    private static func availableFilename(in directory: URL, now: Date, title: String) -> String {
        let timestamp = String(Int(now.timeIntervalSince1970))
        let slug = slug(from: title)
        let base = "manual-\(timestamp)-\(slug)"
        var candidate = "\(base).md"
        var index = 2
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            candidate = "\(base)-\(index).md"
            index += 1
        }
        return candidate
    }

    private static func slug(from title: String) -> String {
        let lowercased = title.lowercased()
        let scalars = lowercased.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(scalar)
            }
            return "-"
        }
        let collapsed = String(scalars)
            .split(separator: "-")
            .prefix(8)
            .joined(separator: "-")
        return collapsed.isEmpty ? "memory" : collapsed
    }

    private static func looksSensitive(_ content: String) -> Bool {
        let patterns = [
            #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#,
            #"(?i)\b(password|passwd|passphrase|api[_ -]?key|secret|token|credential)\s*[:=]"#,
            #"(?i)\b(sk|pk|rk|ghp|github_pat|xox[baprs])[-_][A-Za-z0-9_=\-]{16,}"#
        ]
        return patterns.contains { pattern in
            content.range(of: pattern, options: .regularExpression) != nil
        }
    }
}
