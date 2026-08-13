import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum PrivateFileStoreFileSystemError: LocalizedError, Equatable, Sendable {
    case unsafeDirectory
    case unsafeEntry

    var errorDescription: String? {
        switch self {
        case .unsafeDirectory:
            "The private state directory is not owned by this user or has unsafe permissions."
        case .unsafeEntry:
            "The private state entry is not a private regular file owned by this user."
        }
    }
}

/// Owns descriptor-relative, bounded private-state reads and durable atomic writes.
enum PrivateFileStoreFileSystem {
    private static let directoryPermissions = mode_t(0o700)
    private static let filePermissions = mode_t(0o600)
    private static let readChunkBytes = 64 * 1_024

    /// Reuses one validated directory descriptor across a bounded group of private-file reads.
    /// Holding the descriptor also prevents a path replacement from redirecting later reads.
    final class DirectoryReader {
        private let descriptor: Int32
        private var buffer = [UInt8](repeating: 0, count: 1)

        init?(
            directory: URL,
            repairDirectoryPermissions: Bool = false
        ) throws {
            guard let descriptor = try PrivateFileStoreFileSystem.openDirectory(
                at: directory,
                createIfMissing: false,
                repairPermissions: repairDirectoryPermissions
            ) else {
                return nil
            }
            self.descriptor = descriptor
        }

        deinit {
            PrivateFileStoreFileSystem.closeIgnoringErrors(descriptor)
        }

        func read(
            filename: String,
            maximumBytes: Int,
            requiresPrivateFilePermissions: Bool = true
        ) throws -> Data? {
            guard maximumBytes >= 0 else {
                throw BoundedFileDataError.invalidSizeLimit
            }

            let fileDescriptor = filename.withCString {
                openat(descriptor, $0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
            }
            guard fileDescriptor >= 0 else {
                switch errno {
                case ENOENT:
                    return nil
                case ELOOP:
                    throw BoundedFileDataError.symbolicLink
                default:
                    throw PrivateFileStoreFileSystem.posixError()
                }
            }
            defer { PrivateFileStoreFileSystem.closeIgnoringErrors(fileDescriptor) }

            let metadata = try PrivateFileStoreFileSystem.fileMetadata(fileDescriptor)
            try PrivateFileStoreFileSystem.validateEntry(
                metadata,
                requiresPrivatePermissions: requiresPrivateFilePermissions
            )
            guard metadata.st_size >= 0,
                  UInt64(metadata.st_size) <= UInt64(maximumBytes)
            else {
                throw BoundedFileDataError.exceedsSizeLimit(maximumBytes: maximumBytes)
            }

            let fileSize = Int(metadata.st_size)
            var data = Data()
            data.reserveCapacity(fileSize)
            let requiredBufferSize = min(readChunkBytes, max(1, fileSize))
            if buffer.count < requiredBufferSize {
                buffer = [UInt8](repeating: 0, count: requiredBufferSize)
            }
            while true {
                let remaining = maximumBytes - data.count
                let requested = remaining == 0 ? 1 : min(buffer.count, remaining)
                let count = buffer.withUnsafeMutableBytes { bytes in
                    PrivateFileStoreFileSystem.systemRead(
                        fileDescriptor,
                        bytes.baseAddress,
                        requested
                    )
                }
                if count < 0, errno == EINTR {
                    continue
                }
                guard count >= 0 else {
                    throw PrivateFileStoreFileSystem.posixError()
                }
                guard count > 0 else {
                    return data
                }
                guard count <= remaining else {
                    throw BoundedFileDataError.exceedsSizeLimit(maximumBytes: maximumBytes)
                }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
    }

    static func read(
        directory: URL,
        filename: String,
        maximumBytes: Int,
        requiresPrivateFilePermissions: Bool = true,
        repairDirectoryPermissions: Bool = false
    ) throws -> Data? {
        guard let reader = try DirectoryReader(
            directory: directory,
            repairDirectoryPermissions: repairDirectoryPermissions
        ) else { return nil }
        return try reader.read(
            filename: filename,
            maximumBytes: maximumBytes,
            requiresPrivateFilePermissions: requiresPrivateFilePermissions
        )
    }

    static func write(_ data: Data, directory: URL, filename: String) throws {
        guard let directoryDescriptor = try openDirectory(at: directory, createIfMissing: true) else {
            throw PrivateFileStoreFileSystemError.unsafeDirectory
        }
        defer { closeIgnoringErrors(directoryDescriptor) }

        let temporaryFilename = ".quill-private-\(UUID().uuidString.lowercased()).tmp"
        let descriptor = temporaryFilename.withCString {
            openat(
                directoryDescriptor,
                $0,
                O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                filePermissions
            )
        }
        guard descriptor >= 0 else {
            throw posixError()
        }
        var temporaryEntryExists = true
        defer {
            closeIgnoringErrors(descriptor)
            if temporaryEntryExists {
                temporaryFilename.withCString {
                    _ = unlinkat(directoryDescriptor, $0, 0)
                }
            }
        }

        guard fchmod(descriptor, filePermissions) == 0 else {
            throw posixError()
        }
        try writeAll(data, to: descriptor)
        guard fsync(descriptor) == 0 else {
            throw posixError()
        }

        let renameResult = temporaryFilename.withCString { temporaryName in
            filename.withCString { destinationName in
                renameat(
                    directoryDescriptor,
                    temporaryName,
                    directoryDescriptor,
                    destinationName
                )
            }
        }
        guard renameResult == 0 else {
            throw posixError()
        }
        temporaryEntryExists = false
        try synchronize(directoryDescriptor)
    }

    static func delete(directory: URL, filename: String) throws {
        guard let directoryDescriptor = try openDirectory(at: directory, createIfMissing: false) else {
            return
        }
        defer { closeIgnoringErrors(directoryDescriptor) }

        var metadata = stat()
        let status = filename.withCString {
            fstatat(directoryDescriptor, $0, &metadata, AT_SYMLINK_NOFOLLOW)
        }
        if status != 0 {
            guard errno != ENOENT else { return }
            throw posixError()
        }
        let type = metadata.st_mode & mode_t(S_IFMT)
        guard type == mode_t(S_IFREG) || type == mode_t(S_IFLNK) else {
            throw PrivateFileStoreFileSystemError.unsafeEntry
        }
        guard filename.withCString({ unlinkat(directoryDescriptor, $0, 0) }) == 0 else {
            if errno == ENOENT { return }
            throw posixError()
        }
        try synchronize(directoryDescriptor)
    }

    static func openDirectory(
        at directory: URL,
        createIfMissing: Bool,
        repairPermissions: Bool = false
    ) throws -> Int32? {
        if createIfMissing {
            let parent = directory.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: parent,
                withIntermediateDirectories: true
            )
            do {
                try PrivateDirectory.ensureExists(at: directory)
            } catch let error as CocoaError where error.code == .fileWriteInvalidFileName {
                throw PrivateFileStoreFileSystemError.unsafeDirectory
            }
        }

        let descriptor = directory.path.withCString {
            open($0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else {
            if !createIfMissing, errno == ENOENT {
                return nil
            }
            if errno == ELOOP || errno == ENOTDIR {
                throw PrivateFileStoreFileSystemError.unsafeDirectory
            }
            throw posixError()
        }

        do {
            var metadata = try fileMetadata(descriptor)
            guard metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
                  metadata.st_uid == geteuid()
            else {
                throw PrivateFileStoreFileSystemError.unsafeDirectory
            }
            if createIfMissing || repairPermissions {
                guard fchmod(descriptor, directoryPermissions) == 0 else {
                    throw posixError()
                }
                metadata = try fileMetadata(descriptor)
            }
            guard metadata.st_mode & mode_t(0o077) == 0 else {
                throw PrivateFileStoreFileSystemError.unsafeDirectory
            }
            return descriptor
        } catch {
            closeIgnoringErrors(descriptor)
            throw error
        }
    }

    private static func validateEntry(
        _ metadata: stat,
        requiresPrivatePermissions: Bool
    ) throws {
        guard metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            throw PrivateFileStoreFileSystemError.unsafeEntry
        }
        // A concurrent atomic replacement can unlink this already-open inode before fstat, which
        // safely produces link count zero. More than one link can expose the secret elsewhere.
        guard metadata.st_uid == geteuid(), metadata.st_nlink <= 1 else {
            throw PrivateFileStoreFileSystemError.unsafeEntry
        }
        guard !requiresPrivatePermissions || metadata.st_mode & mode_t(0o077) == 0 else {
            throw PrivateFileStoreFileSystemError.unsafeEntry
        }
    }

    static func fileMetadata(_ descriptor: Int32) throws -> stat {
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0 else {
            throw posixError()
        }
        return metadata
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = systemWrite(
                    descriptor,
                    bytes.baseAddress?.advanced(by: offset),
                    bytes.count - offset
                )
                if count < 0, errno == EINTR {
                    continue
                }
                guard count > 0 else {
                    throw posixError()
                }
                offset += count
            }
        }
    }

    static func synchronize(_ descriptor: Int32) throws {
        guard fsync(descriptor) == 0 else {
            throw posixError()
        }
    }

    static func closeIgnoringErrors(_ descriptor: Int32) {
        guard descriptor >= 0 else { return }
        _ = close(descriptor)
    }

    static func posixError(_ code: Int32 = errno) -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(code))
    }

    private static func systemRead(
        _ descriptor: Int32,
        _ buffer: UnsafeMutableRawPointer?,
        _ count: Int
    ) -> Int {
#if canImport(Darwin)
        Darwin.read(descriptor, buffer, count)
#else
        Glibc.read(descriptor, buffer, count)
#endif
    }

    private static func systemWrite(
        _ descriptor: Int32,
        _ buffer: UnsafeRawPointer?,
        _ count: Int
    ) -> Int {
#if canImport(Darwin)
        Darwin.write(descriptor, buffer, count)
#else
        Glibc.write(descriptor, buffer, count)
#endif
    }
}
