import Foundation
import QuillCodeCore

extension AppServerSession {
    static let maximumReadFileBytes = 512 * 1_024 * 1_024

    func readFile(_ value: CLIJSONValue) throws -> CLIJSONValue {
        let path = try fileSystemPath(from: value, key: "path")
        do {
            let metadata = try AppServerFileMetadata.load(at: path)
            guard metadata.isFile else {
                throw AppServerRPCError.invalidRequest("path `\(path.path)` is not a file")
            }
            guard metadata.size <= Self.maximumReadFileBytes else {
                throw AppServerRPCError.invalidRequest(Self.fileTooLargeMessage)
            }
            let handle = try FileHandle(forReadingFrom: path)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: Self.maximumReadFileBytes + 1) ?? Data()
            guard data.count <= Self.maximumReadFileBytes else {
                throw AppServerRPCError.invalidRequest(Self.fileTooLargeMessage)
            }
            return .object(["dataBase64": .string(data.base64EncodedString())])
        } catch let error as AppServerRPCError {
            throw error
        } catch {
            throw fileSystemError("fs/readFile", error)
        }
    }

    func writeFile(_ value: CLIJSONValue) throws -> CLIJSONValue {
        let params = try AppServerParams(value)
        let path = try fileSystemPath(from: params, key: "path")
        let encoded = try params.requiredString("dataBase64", allowingEmpty: true)
        guard let data = Data(base64Encoded: encoded) else {
            throw AppServerRPCError.invalidRequest(
                "fs/writeFile requires valid base64 dataBase64: invalid base64 encoding"
            )
        }
        do {
            try data.write(to: path)
            return .object([:])
        } catch {
            throw fileSystemError("fs/writeFile", error)
        }
    }

    func createDirectory(_ value: CLIJSONValue) throws -> CLIJSONValue {
        let params = try AppServerParams(value)
        let path = try fileSystemPath(from: params, key: "path")
        let recursive = try params.optionalBool("recursive") ?? true
        do {
            try FileManager.default.createDirectory(
                at: path,
                withIntermediateDirectories: recursive
            )
            return .object([:])
        } catch {
            throw fileSystemError("fs/createDirectory", error)
        }
    }

    func fileMetadata(_ value: CLIJSONValue) throws -> CLIJSONValue {
        let path = try fileSystemPath(from: value, key: "path")
        do {
            let metadata = try AppServerFileMetadata.load(at: path)
            return metadata.json
        } catch {
            throw fileSystemError("fs/getMetadata", error)
        }
    }

    func readDirectory(_ value: CLIJSONValue) throws -> CLIJSONValue {
        let path = try fileSystemPath(from: value, key: "path")
        do {
            let entries = try FileManager.default.contentsOfDirectory(
                at: path,
                includingPropertiesForKeys: AppServerFileMetadata.resourceKeys,
                options: []
            ).sorted { $0.lastPathComponent < $1.lastPathComponent }
            return .object([
                "entries": .array(entries.compactMap { entry -> CLIJSONValue? in
                    guard let metadata = try? AppServerFileMetadata.load(at: entry) else {
                        return nil
                    }
                    return CLIJSONValue.object([
                        "fileName": .string(entry.lastPathComponent),
                        "isDirectory": .bool(metadata.isDirectory),
                        "isFile": .bool(metadata.isFile)
                    ])
                })
            ])
        } catch {
            throw fileSystemError("fs/readDirectory", error)
        }
    }

    func removeFileSystemItem(_ value: CLIJSONValue) throws -> CLIJSONValue {
        let params = try AppServerParams(value)
        let path = try fileSystemPath(from: params, key: "path")
        let recursive = try params.optionalBool("recursive") ?? true
        let force = try params.optionalBool("force") ?? true
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: path.path) || AppServerFileMetadata.isSymbolicLink(path) else {
            if force { return .object([:]) }
            throw AppServerRPCError.internalError("fs/remove failed: item does not exist at \(path.path)")
        }

        do {
            if AppServerFileMetadata.isSymbolicLink(path) {
                try fileManager.removeItem(at: path)
                return .object([:])
            }
            let metadata = try AppServerFileMetadata.load(at: path)
            if metadata.isDirectory, !recursive {
                let children = try fileManager.contentsOfDirectory(atPath: path.path)
                guard children.isEmpty else {
                    throw AppServerRPCError.internalError(
                        "fs/remove failed: directory is not empty at \(path.path)"
                    )
                }
            }
            try fileManager.removeItem(at: path)
            return .object([:])
        } catch let error as AppServerRPCError {
            throw error
        } catch {
            throw fileSystemError("fs/remove", error)
        }
    }

    func copyFileSystemItem(_ value: CLIJSONValue) throws -> CLIJSONValue {
        let params = try AppServerParams(value)
        let source = try fileSystemPath(from: params, key: "sourcePath")
        let destination = try fileSystemPath(from: params, key: "destinationPath")
        let recursive = try params.optionalBool("recursive") ?? false

        do {
            try AppServerFileCopier.copy(
                from: source,
                to: destination,
                recursive: recursive
            )
            return .object([:])
        } catch let error as AppServerRPCError {
            throw error
        } catch {
            throw fileSystemError("fs/copy", error)
        }
    }

    func startFileWatch(_ value: CLIJSONValue) throws -> CLIJSONValue {
        let params = try AppServerParams(value)
        let watchID = try params.requiredString("watchId")
        guard fileWatches[watchID] == nil else {
            throw AppServerRPCError.invalidRequest("watchId already exists: \(watchID)")
        }
        let path = try fileSystemPath(from: params, key: "path")
        let task = AppServerFileWatcher.monitor(path: path) { [weak self] changedPaths in
            await self?.fileWatchChanged(watchID: watchID, changedPaths: changedPaths)
        }
        fileWatches[watchID] = AppServerFileWatchRegistration(task: task)
        return .object(["path": .string(path.path)])
    }

    func stopFileWatch(_ value: CLIJSONValue) async throws -> CLIJSONValue {
        let params = try AppServerParams(value)
        let watchID = try params.requiredString("watchId")
        if let registration = fileWatches.removeValue(forKey: watchID) {
            registration.task.cancel()
            await registration.task.value
        }
        return .object([:])
    }

    func cancelAllFileWatches() {
        let registrations = fileWatches.values
        fileWatches.removeAll(keepingCapacity: false)
        for registration in registrations {
            registration.task.cancel()
        }
    }

    private func fileWatchChanged(watchID: String, changedPaths: [URL]) async {
        guard fileWatches[watchID] != nil, !inputFinished else { return }
        await sendNotification("fs/changed", params: .object([
            "watchId": .string(watchID),
            "changedPaths": .array(changedPaths.map { .string($0.standardizedFileURL.path) })
        ]))
    }

    private func fileSystemPath(from value: CLIJSONValue, key: String) throws -> URL {
        try fileSystemPath(from: AppServerParams(value), key: key)
    }

    private func fileSystemPath(from params: AppServerParams, key: String) throws -> URL {
        let rawPath = try params.requiredString(key)
        guard NSString(string: rawPath).isAbsolutePath, !rawPath.contains("\0") else {
            throw AppServerRPCError.invalidRequest(
                "Invalid request: AbsolutePathBuf deserialized without a base path"
            )
        }
        return URL(fileURLWithPath: rawPath).standardizedFileURL
    }

    private func fileSystemError(_ method: String, _ error: Error) -> AppServerRPCError {
        AppServerRPCError.internalError("\(method) failed: \(error.localizedDescription)")
    }

    private static var fileTooLargeMessage: String {
        "file is too large to read: limit is \(maximumReadFileBytes) bytes"
    }
}

struct AppServerFileWatchRegistration: Sendable {
    var task: Task<Void, Never>
}

private struct AppServerFileMetadata: Sendable, Equatable {
    static let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey,
        .isRegularFileKey,
        .isSymbolicLinkKey,
        .creationDateKey,
        .contentModificationDateKey,
        .fileSizeKey,
        .fileResourceIdentifierKey
    ]

    var isDirectory: Bool
    var isFile: Bool
    var isSymbolicLink: Bool
    var createdAt: Date?
    var modifiedAt: Date?
    var size: Int
    var resourceIdentifier: String?

    static func load(at url: URL) throws -> AppServerFileMetadata {
        var uncachedURL = url
        uncachedURL.removeAllCachedResourceValues()
        let linkValues = try uncachedURL.resourceValues(forKeys: [.isSymbolicLinkKey])
        let isSymbolicLink = linkValues.isSymbolicLink == true
        if isSymbolicLink {
            uncachedURL = url.resolvingSymlinksInPath()
            uncachedURL.removeAllCachedResourceValues()
        }
        let values = try uncachedURL.resourceValues(forKeys: Set(resourceKeys))
        return AppServerFileMetadata(
            isDirectory: values.isDirectory == true,
            isFile: values.isRegularFile == true,
            isSymbolicLink: isSymbolicLink,
            createdAt: values.creationDate,
            modifiedAt: values.contentModificationDate,
            size: values.fileSize ?? 0,
            resourceIdentifier: values.fileResourceIdentifier.map { String(describing: $0) }
        )
    }

    static func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    var json: CLIJSONValue {
        .object([
            "isDirectory": .bool(isDirectory),
            "isFile": .bool(isFile),
            "isSymlink": .bool(isSymbolicLink),
            "createdAtMs": .number(Self.milliseconds(createdAt)),
            "modifiedAtMs": .number(Self.milliseconds(modifiedAt))
        ])
    }

    private static func milliseconds(_ date: Date?) -> Double {
        guard let date else { return 0 }
        return (date.timeIntervalSince1970 * 1_000).rounded(.towardZero)
    }
}

private enum AppServerFileCopier {
    static func copy(from source: URL, to destination: URL, recursive: Bool) throws {
        if AppServerFileMetadata.isSymbolicLink(source) {
            try copySymbolicLink(from: source, to: destination)
            return
        }
        let metadata = try AppServerFileMetadata.load(at: source)
        if metadata.isDirectory {
            guard recursive else {
                throw AppServerRPCError.invalidRequest(
                    "fs/copy requires recursive: true when sourcePath is a directory"
                )
            }
            guard !isSameOrDescendant(destination, of: source) else {
                throw AppServerRPCError.invalidRequest(
                    "fs/copy cannot copy a directory to itself or one of its descendants"
                )
            }
            try copyDirectory(from: source, to: destination)
        } else if metadata.isFile {
            try copyRegularFile(from: source, to: destination)
        } else {
            throw AppServerRPCError.invalidRequest(
                "fs/copy only supports regular files, directories, and symlinks"
            )
        }
    }

    private static func copyDirectory(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let entries = try fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: AppServerFileMetadata.resourceKeys,
            options: []
        )
        for entry in entries {
            let target = destination.appendingPathComponent(entry.lastPathComponent)
            let metadata = try AppServerFileMetadata.load(at: entry)
            if metadata.isSymbolicLink {
                try copySymbolicLink(from: entry, to: target)
            } else if metadata.isDirectory {
                try copyDirectory(from: entry, to: target)
            } else if metadata.isFile {
                try copyRegularFile(from: entry, to: target)
            }
        }
    }

    private static func copyRegularFile(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: destination.path)
                || AppServerFileMetadata.isSymbolicLink(destination) else {
            try fileManager.copyItem(at: source, to: destination)
            return
        }

        let sourceHandle = try FileHandle(forReadingFrom: source)
        defer { try? sourceHandle.close() }
        let destinationHandle = try FileHandle(forWritingTo: destination)
        defer { try? destinationHandle.close() }
        try destinationHandle.truncate(atOffset: 0)
        while let chunk = try sourceHandle.read(upToCount: 1_024 * 1_024), !chunk.isEmpty {
            try destinationHandle.write(contentsOf: chunk)
        }

        let attributes = try fileManager.attributesOfItem(atPath: source.path)
        if let permissions = attributes[.posixPermissions] {
            try fileManager.setAttributes(
                [.posixPermissions: permissions],
                ofItemAtPath: destination.path
            )
        }
    }

    private static func copySymbolicLink(from source: URL, to destination: URL) throws {
        let target = try FileManager.default.destinationOfSymbolicLink(atPath: source.path)
        try FileManager.default.createSymbolicLink(
            atPath: destination.path,
            withDestinationPath: target
        )
    }

    private static func isSameOrDescendant(_ candidate: URL, of root: URL) -> Bool {
        let candidatePath = candidate.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        let lexicallyInside = candidatePath == rootPath || candidatePath.hasPrefix(
            rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        )
        if lexicallyInside { return true }
        return WorkspaceBoundary.isInside(
            WorkspaceBoundary.symlinkResolvedPath(candidate),
            root: WorkspaceBoundary.symlinkResolvedPath(root)
        )
    }
}
