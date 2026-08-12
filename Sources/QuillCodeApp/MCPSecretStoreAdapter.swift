import Foundation
import QuillCodePersistence
import QuillCodeTools

/// Bridges the persistence layer's `QuillSecretStore` to the tools layer's `MCPSecretStore`, so
/// remote MCP OAuth tokens use the same platform credential store as the TrustedRouter API key.
/// Defined here because this is the only target depending on both persistence and tools.
struct MCPSecretStoreAdapter: MCPSecretStore {
    let backing: any QuillSecretStore

    func read(_ key: String) throws -> String? {
        try backing.read(key)
    }

    func write(_ value: String, for key: String) throws {
        try backing.write(value, for: key)
    }

    func delete(_ key: String) throws {
        try backing.delete(key)
    }
}
