import Foundation
import QuillCodePersistence

public struct SecretTrustedRouterSessionStore: TrustedRouterSessionStore {
    public var secretStore: QuillSecretStore
    public var key: String

    public init(
        secretStore: QuillSecretStore,
        key: String = QuillSecretKeys.trustedRouterAPIKey
    ) {
        self.secretStore = secretStore
        self.key = key
    }

    public var hasAPIKey: Bool {
        let value = try? apiKey()
        return value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    public func apiKey() throws -> String? {
        try secretStore.read(key)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func saveAPIKey(_ key: String) throws {
        try secretStore.write(key, for: self.key)
    }
}
