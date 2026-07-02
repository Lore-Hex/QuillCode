import Foundation
import QuillCodePersistence
import QuillCodeTools

/// Bridges the persistence layer's `QuillSecretStore` to the tools layer's `MCPSecretStore`, so
/// remote MCP OAuth tokens land in the same `~/.quillcode/secrets` file store that holds the
/// TrustedRouter API key. Defined in `QuillCodeApp` because it is the only target depending on
/// both `QuillCodePersistence` and `QuillCodeTools`.
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
