import Foundation

#if canImport(Security)
import Security
#endif

public enum QuillSecretStoreFactory {
    public static let macOSService = "co.lorehex.QuillCowork.secrets"

    public static func make(for paths: QuillCodePaths) -> any QuillSecretStore {
        #if canImport(Security)
        let signingTeamIdentifier = Bundle.main.object(
            forInfoDictionaryKey: "QuillCodeSigningTeamIdentifier"
        ) as? String
        return make(for: paths, signingTeamIdentifier: signingTeamIdentifier)
        #else
        return FileSecretStore(directory: paths.secretsDirectory)
        #endif
    }

    #if canImport(Security)
    static func make(
        for paths: QuillCodePaths,
        signingTeamIdentifier: String?
    ) -> any QuillSecretStore {
        let legacy = FileSecretStore(directory: paths.secretsDirectory)
        guard paths.secretStorageScope == .userAccount,
              isValidTeamIdentifier(signingTeamIdentifier) else {
            return legacy
        }

        // Ad-hoc designated requirements are build-specific hashes. Wait for the stable Developer
        // ID identity so Keychain access survives an ordinary app update without prompting.
        return LegacyMigratingSecretStore(
            primary: KeychainSecretStore(service: macOSService),
            legacy: legacy
        )
    }

    private static func isValidTeamIdentifier(_ value: String?) -> Bool {
        guard let value, value.utf8.count == 10 else { return false }
        return value.utf8.allSatisfy { byte in
            (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
                || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
        }
    }
    #endif
}

public struct LegacyMigratingSecretStore: QuillSecretStore {
    public var primary: any QuillSecretStore
    public var legacy: any QuillSecretStore

    public init(primary: any QuillSecretStore, legacy: any QuillSecretStore) {
        self.primary = primary
        self.legacy = legacy
    }

    public func read(_ key: String) throws -> String? {
        if let value = try primary.read(key) {
            try? legacy.delete(key)
            return value
        }
        guard let value = try legacy.read(key) else { return nil }

        try primary.write(value, for: key)
        try? legacy.delete(key)
        return value
    }

    public func write(_ value: String, for key: String) throws {
        try primary.write(value, for: key)
        try legacy.delete(key)
    }

    public func delete(_ key: String) throws {
        // Remove fallback material first so a failed primary deletion cannot be undone by migration.
        try legacy.delete(key)
        try primary.delete(key)
    }
}

#if canImport(Security)
public enum KeychainSecretStoreError: LocalizedError, Equatable, Sendable {
    case invalidService
    case invalidKey
    case invalidUTF8
    case valueExceedsSizeLimit(maximumBytes: Int)
    case operationFailed(operation: String, status: OSStatus)

    public var errorDescription: String? {
        switch self {
        case .invalidService:
            return "The Keychain service identifier is invalid."
        case .invalidKey:
            return "The Keychain secret key is invalid."
        case .invalidUTF8:
            return "The Keychain secret is not valid UTF-8."
        case .valueExceedsSizeLimit(let maximumBytes):
            return "The secret exceeds the \(maximumBytes)-byte Keychain storage limit."
        case .operationFailed(let operation, let status):
            let detail = SecCopyErrorMessageString(status, nil) as String?
                ?? "OSStatus \(status)"
            return "Keychain \(operation) failed: \(detail)."
        }
    }
}

public struct KeychainSecretStore: QuillSecretStore {
    public static let maximumValueBytes = FileSecretStore.maximumValueBytes
    public static let maximumIdentifierBytes = 4 * 1_024

    public var service: String

    public init(service: String) {
        self.service = service
    }

    public func read(_ key: String) throws -> String? {
        let query = try baseQuery(for: key).merging([
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]) { _, new in new }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainSecretStoreError.operationFailed(operation: "read", status: status)
        }
        guard let data = result as? Data else {
            throw KeychainSecretStoreError.invalidUTF8
        }
        guard data.count <= Self.maximumValueBytes else {
            throw KeychainSecretStoreError.valueExceedsSizeLimit(
                maximumBytes: Self.maximumValueBytes
            )
        }
        guard let value = String(data: data, encoding: .utf8) else {
            throw KeychainSecretStoreError.invalidUTF8
        }
        return value
    }

    public func write(_ value: String, for key: String) throws {
        let data = Data(value.utf8)
        guard data.count <= Self.maximumValueBytes else {
            throw KeychainSecretStoreError.valueExceedsSizeLimit(
                maximumBytes: Self.maximumValueBytes
            )
        }
        let query = try baseQuery(for: key)
        let attributes = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainSecretStoreError.operationFailed(operation: "update", status: updateStatus)
        }

        let addition = query.merging([
            kSecValueData as String: data
        ]) { _, new in new }
        let addStatus = SecItemAdd(addition as CFDictionary, nil)
        if addStatus == errSecSuccess { return }
        if addStatus == errSecDuplicateItem {
            let retryStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard retryStatus == errSecSuccess else {
                throw KeychainSecretStoreError.operationFailed(
                    operation: "concurrent update",
                    status: retryStatus
                )
            }
            return
        }
        throw KeychainSecretStoreError.operationFailed(operation: "add", status: addStatus)
    }

    public func delete(_ key: String) throws {
        let status = SecItemDelete(try baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainSecretStoreError.operationFailed(operation: "delete", status: status)
        }
    }

    private func baseQuery(for key: String) throws -> [String: Any] {
        guard isValidIdentifier(service) else {
            throw KeychainSecretStoreError.invalidService
        }
        guard isValidIdentifier(key) else {
            throw KeychainSecretStoreError.invalidKey
        }
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: false
        ]
    }

    private func isValidIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= Self.maximumIdentifierBytes
    }
}
#endif
