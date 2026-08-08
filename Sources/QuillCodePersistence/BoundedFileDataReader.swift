import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum BoundedFileDataError: LocalizedError, Equatable, Sendable {
    case invalidSizeLimit
    case notRegularFile
    case symbolicLink
    case exceedsSizeLimit(maximumBytes: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidSizeLimit:
            "The file loading limit is invalid."
        case .notRegularFile:
            "The path is not a regular file."
        case .symbolicLink:
            "The path is a symbolic link."
        case .exceedsSizeLimit(let maximumBytes):
            "The file exceeds the \(maximumBytes)-byte loading limit."
        }
    }
}

/// Reads a known persistence file without following links or mapping an unbounded payload.
public enum BoundedFileDataReader {
    public static func readIfPresent(from fileURL: URL, maximumBytes: Int) throws -> Data? {
        do {
            return try read(from: fileURL, maximumBytes: maximumBytes)
        } catch let error as NSError
            where error.domain == NSCocoaErrorDomain
                && error.code == NSFileReadNoSuchFileError {
            return nil
        }
    }

    public static func read(from fileURL: URL, maximumBytes: Int) throws -> Data {
        guard maximumBytes >= 0 else {
            throw BoundedFileDataError.invalidSizeLimit
        }
#if canImport(Darwin) || canImport(Glibc)
        let descriptor = fileURL.path.withCString {
            open($0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else {
            let code = errno
            if code == ELOOP {
                throw BoundedFileDataError.symbolicLink
            }
            if code == ENOENT {
                throw NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSFileReadNoSuchFileError,
                    userInfo: [NSFilePathErrorKey: fileURL.path]
                )
            }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }

        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        guard metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            throw BoundedFileDataError.notRegularFile
        }
        guard metadata.st_size >= 0,
              UInt64(metadata.st_size) <= UInt64(maximumBytes)
        else {
            throw BoundedFileDataError.exceedsSizeLimit(maximumBytes: maximumBytes)
        }

        var data = Data()
        data.reserveCapacity(Int(metadata.st_size))
        while true {
            let remainingBytes = maximumBytes - data.count
            let requestedBytes = remainingBytes == 0 ? 1 : min(64 * 1_024, remainingBytes)
            guard let chunk = try handle.read(upToCount: requestedBytes), !chunk.isEmpty else {
                return data
            }
            guard chunk.count <= remainingBytes else {
                throw BoundedFileDataError.exceedsSizeLimit(maximumBytes: maximumBytes)
            }
            data.append(chunk)
        }
#else
        let values = try fileURL.resourceValues(forKeys: [
            .fileSizeKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ])
        guard values.isSymbolicLink != true else {
            throw BoundedFileDataError.symbolicLink
        }
        guard values.isRegularFile == true else {
            throw BoundedFileDataError.notRegularFile
        }
        guard let fileSize = values.fileSize,
              fileSize >= 0,
              fileSize <= maximumBytes
        else {
            throw BoundedFileDataError.exceedsSizeLimit(maximumBytes: maximumBytes)
        }
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        guard data.count <= maximumBytes else {
            throw BoundedFileDataError.exceedsSizeLimit(maximumBytes: maximumBytes)
        }
        return data
#endif
    }
}
