import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

#if canImport(Darwin)
private typealias DirectoryHandle = UnsafeMutablePointer<DIR>
#else
private typealias DirectoryHandle = OpaquePointer
#endif

enum FileSystemIO {
    struct DirectoryEntry: Sendable, Hashable {
        var url: URL
        var kind: String
        var bytes: Int?
    }

    static func readFile(at url: URL) throws -> Data {
        let descriptor = try openForReading(url.path)
        defer { _ = systemClose(descriptor) }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes {
                systemRead(descriptor, $0.baseAddress, $0.count)
            }
            if count > 0 {
                data.append(buffer, count: count)
            } else if count == 0 {
                return data
            } else if errno != EINTR {
                throw posixError(operation: "read", path: url.path)
            }
        }
    }

    static func directoryEntries(at directoryURL: URL) throws -> [DirectoryEntry] {
        let directory = try openDirectory(directoryURL.path)
        defer { _ = closedir(directory) }

        var entries: [DirectoryEntry] = []
        while true {
            errno = 0
            guard let entry = readdir(directory) else {
                if errno == 0 {
                    return entries
                }
                if errno == EINTR {
                    continue
                }
                throw posixError(operation: "readdir", path: directoryURL.path)
            }

            let name = withUnsafePointer(to: entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: entry.pointee.d_name)) {
                    String(cString: $0)
                }
            }
            guard name != ".", name != ".." else { continue }
            let url = directoryURL.appendingPathComponent(name, isDirectory: false)
            let metadata = metadata(atPath: url.path)
            entries.append(DirectoryEntry(
                url: url,
                kind: metadata.kind,
                bytes: metadata.bytes
            ))
        }
    }

    private static func openForReading(_ path: String) throws -> Int32 {
        while true {
            let descriptor = path.withCString { systemOpen($0, O_RDONLY | O_CLOEXEC) }
            if descriptor >= 0 {
                return descriptor
            }
            guard errno == EINTR else {
                throw posixError(operation: "open", path: path)
            }
        }
    }

    private static func openDirectory(_ path: String) throws -> DirectoryHandle {
        while true {
            if let directory = path.withCString({ opendir($0) }) {
                return directory
            }
            guard errno == EINTR else {
                throw posixError(operation: "opendir", path: path)
            }
        }
    }

    private static func metadata(atPath path: String) -> (kind: String, bytes: Int?) {
        var info = stat()
        var result: Int32
        repeat {
            result = path.withCString { lstat($0, &info) }
        } while result != 0 && errno == EINTR
        guard result == 0 else { return ("other", nil) }

        let fileType = info.st_mode & mode_t(S_IFMT)
        if fileType == mode_t(S_IFLNK) {
            return ("symlink", nil)
        }
        if fileType == mode_t(S_IFDIR) {
            return ("directory", nil)
        }
        if fileType == mode_t(S_IFREG) {
            return ("file", Int(exactly: info.st_size))
        }
        return ("other", nil)
    }

    private static func posixError(operation: String, path: String) -> NSError {
        let code = errno
        return NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(code),
            userInfo: [
                NSLocalizedDescriptionKey:
                    "\(operation) failed for \(path): \(String(cString: strerror(code)))"
            ]
        )
    }

    private static func systemOpen(_ path: UnsafePointer<CChar>, _ flags: Int32) -> Int32 {
#if canImport(Darwin)
        Darwin.open(path, flags)
#else
        Glibc.open(path, flags)
#endif
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

    private static func systemClose(_ descriptor: Int32) -> Int32 {
#if canImport(Darwin)
        Darwin.close(descriptor)
#else
        Glibc.close(descriptor)
#endif
    }
}
