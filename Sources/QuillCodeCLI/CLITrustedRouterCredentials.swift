import Foundation
import QuillCodeAgent
import QuillCodePersistence

enum CLITrustedRouterCredentials {
    static func resolve(
        explicit: String?,
        environment: [String: String],
        sessionStore: any TrustedRouterSessionStore
    ) throws -> String? {
        for candidate in [
            explicit,
            environment["QUILLCODE_API_KEY"],
            environment["TRUSTEDROUTER_API_KEY"]
        ] {
            if let value = normalized(candidate) { return value }
        }
        return normalized(try sessionStore.apiKey())
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension AppServerSession {
    func resolvedTrustedRouterAPIKey() throws -> String? {
        try CLITrustedRouterCredentials.resolve(
            explicit: request.apiKey,
            environment: environment,
            sessionStore: SecretTrustedRouterSessionStore(
                secretStore: FileSecretStore(directory: paths.secretsDirectory)
            )
        )
    }
}
