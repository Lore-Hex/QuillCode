import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// `flock` protects cooperating processes, but Darwin treats locks from sibling threads in the
/// same process as one owner. Reference counting keeps only the currently active local locks.
private final class PrivateFileStoreLocalLockRegistry: @unchecked Sendable {
    static let shared = PrivateFileStoreLocalLockRegistry()

    private final class Entry {
        let lock = NSLock()
        var referenceCount = 0
    }

    private let registryLock = NSLock()
    private var entries: [String: Entry] = [:]

    func withLock<Value>(for key: String, operation: () throws -> Value) rethrows -> Value {
        registryLock.lock()
        let entry: Entry
        if let existing = entries[key] {
            entry = existing
        } else {
            entry = Entry()
            entries[key] = entry
        }
        entry.referenceCount += 1
        registryLock.unlock()

        entry.lock.lock()
        defer {
            entry.lock.unlock()
            registryLock.lock()
            entry.referenceCount -= 1
            if entry.referenceCount == 0 {
                entries.removeValue(forKey: key)
            }
            registryLock.unlock()
        }
        return try operation()
    }
}

/// Serializes read-modify-write mutations across app tasks and cooperating processes.
enum PrivateFileStoreMutationCoordinator {
    private static let filePermissions = mode_t(0o600)

    static func withExclusiveLock<Value>(
        directory: URL,
        filename: String,
        operation: () throws -> Value
    ) throws -> Value {
        let lockIdentity = directory.resolvingSymlinksInPath().standardizedFileURL.path
            + "\0" + filename
        return try PrivateFileStoreLocalLockRegistry.shared.withLock(for: lockIdentity) {
            try withProcessLock(directory: directory, filename: filename, operation: operation)
        }
    }

    static func moveAside(
        directory: URL,
        filename: String,
        backupFilename: String
    ) throws {
        guard let directoryDescriptor = try PrivateFileStoreFileSystem.openDirectory(
            at: directory,
            createIfMissing: false
        ) else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT))
        }
        defer { PrivateFileStoreFileSystem.closeIgnoringErrors(directoryDescriptor) }

        var metadata = stat()
        let sourceStatus = filename.withCString {
            fstatat(directoryDescriptor, $0, &metadata, AT_SYMLINK_NOFOLLOW)
        }
        guard sourceStatus == 0 else {
            throw PrivateFileStoreFileSystem.posixError()
        }
        guard metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            throw PrivateFileStoreFileSystemError.unsafeEntry
        }

        let linkResult = filename.withCString { sourceName in
            backupFilename.withCString { backupName in
                linkat(directoryDescriptor, sourceName, directoryDescriptor, backupName, 0)
            }
        }
        guard linkResult == 0 else {
            throw PrivateFileStoreFileSystem.posixError()
        }
        do {
            try PrivateFileStoreFileSystem.synchronize(directoryDescriptor)
        } catch {
            backupFilename.withCString { _ = unlinkat(directoryDescriptor, $0, 0) }
            throw error
        }
        guard filename.withCString({ unlinkat(directoryDescriptor, $0, 0) }) == 0 else {
            let error = PrivateFileStoreFileSystem.posixError()
            backupFilename.withCString { _ = unlinkat(directoryDescriptor, $0, 0) }
            throw error
        }
        // The backup is now the only durable owner of the bytes, so retain it on sync failure.
        try PrivateFileStoreFileSystem.synchronize(directoryDescriptor)
    }

    private static func withProcessLock<Value>(
        directory: URL,
        filename: String,
        operation: () throws -> Value
    ) throws -> Value {
        guard let directoryDescriptor = try PrivateFileStoreFileSystem.openDirectory(
            at: directory,
            createIfMissing: true
        ) else {
            throw PrivateFileStoreFileSystemError.unsafeDirectory
        }
        defer { PrivateFileStoreFileSystem.closeIgnoringErrors(directoryDescriptor) }

        let lockFilename = ".\(filename).lock"
        let descriptor = lockFilename.withCString {
            openat(
                directoryDescriptor,
                $0,
                O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW,
                filePermissions
            )
        }
        guard descriptor >= 0 else {
            throw PrivateFileStoreFileSystem.posixError()
        }
        defer { PrivateFileStoreFileSystem.closeIgnoringErrors(descriptor) }

        let metadata = try PrivateFileStoreFileSystem.fileMetadata(descriptor)
        guard metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              metadata.st_uid == geteuid(),
              metadata.st_nlink <= 1
        else {
            throw PrivateFileStoreFileSystemError.unsafeEntry
        }
        guard fchmod(descriptor, filePermissions) == 0 else {
            throw PrivateFileStoreFileSystem.posixError()
        }
        while flock(descriptor, LOCK_EX) != 0 {
            guard errno == EINTR else { throw PrivateFileStoreFileSystem.posixError() }
        }
        defer { _ = flock(descriptor, LOCK_UN) }
        return try operation()
    }
}
