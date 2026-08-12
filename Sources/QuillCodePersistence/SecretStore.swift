import Foundation

public enum QuillSecretKeys {
    public static let trustedRouterAPIKey = "trustedrouter:api_key"
}

public protocol QuillSecretStore: Sendable {
    func read(_ key: String) throws -> String?
    func write(_ value: String, for key: String) throws
    func delete(_ key: String) throws
}

public enum FileSecretStoreError: LocalizedError, Equatable, Sendable {
    case invalidUTF8
    case unsafeDirectory
    case unsafeSecretEntry
    case valueExceedsSizeLimit(maximumBytes: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidUTF8:
            "The stored secret is not valid UTF-8."
        case .unsafeDirectory:
            "The secret-store directory is not a private directory owned by this user."
        case .unsafeSecretEntry:
            "The secret-store entry is not a private regular file owned by this user."
        case .valueExceedsSizeLimit(let maximumBytes):
            "The secret exceeds the \(maximumBytes)-byte storage limit."
        }
    }
}

public struct FileSecretStore: QuillSecretStore {
    public static let maximumValueBytes = 1 * 1_024 * 1_024

    public var directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func read(_ key: String) throws -> String? {
        guard let data = try FileSecretStoreFileSystem.read(
            directory: directory,
            filename: filename(for: key),
            maximumBytes: Self.maximumValueBytes
        ) else {
            return nil
        }
        guard let value = String(data: data, encoding: .utf8) else {
            throw FileSecretStoreError.invalidUTF8
        }
        return value
    }

    public func write(_ value: String, for key: String) throws {
        let data = Data(value.utf8)
        guard data.count <= Self.maximumValueBytes else {
            throw FileSecretStoreError.valueExceedsSizeLimit(
                maximumBytes: Self.maximumValueBytes
            )
        }
        try FileSecretStoreFileSystem.write(
            data,
            directory: directory,
            filename: filename(for: key)
        )
    }

    public func delete(_ key: String) throws {
        try FileSecretStoreFileSystem.delete(
            directory: directory,
            filename: filename(for: key)
        )
    }

    private func filename(for key: String) -> String {
        let safe = key.unicodeScalars.map { scalar -> Character in
            switch scalar {
            case "a"..."z", "A"..."Z", "0"..."9", ".", "_", "-":
                return Character(scalar)
            default:
                return "_"
            }
        }
        let filename = String(safe).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return filename.isEmpty ? "secret" : filename
    }
}
