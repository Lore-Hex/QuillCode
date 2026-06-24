import Foundation

public enum QuillSecretKeys {
    public static let trustedRouterAPIKey = "trustedrouter:api_key"
}

public protocol QuillSecretStore: Sendable {
    func read(_ key: String) throws -> String?
    func write(_ value: String, for key: String) throws
    func delete(_ key: String) throws
}

public struct FileSecretStore: QuillSecretStore {
    private static let directoryPermissions = 0o700
    private static let filePermissions = 0o600

    public var directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func read(_ key: String) throws -> String? {
        let url = fileURL(for: key)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try String(contentsOf: url, encoding: .utf8)
    }

    public func write(_ value: String, for key: String) throws {
        try prepareDirectory()
        let url = fileURL(for: key)
        try value.write(to: url, atomically: true, encoding: .utf8)
        try protectFile(url)
    }

    public func delete(_ key: String) throws {
        let url = fileURL(for: key)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func fileURL(for key: String) -> URL {
        let safe = key.unicodeScalars.map { scalar -> Character in
            switch scalar {
            case "a"..."z", "A"..."Z", "0"..."9", ".", "_", "-":
                return Character(scalar)
            default:
                return "_"
            }
        }
        let filename = String(safe).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return directory.appendingPathComponent(filename.isEmpty ? "secret" : filename)
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: Self.directoryPermissions]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: Self.directoryPermissions],
            ofItemAtPath: directory.path
        )
    }

    private func protectFile(_ url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: Self.filePermissions],
            ofItemAtPath: url.path
        )
    }
}
