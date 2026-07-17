import Foundation

enum ClaudeCodeImportSanitizer {
    private static let replacement = "<redacted; configure again in QuillCode>"

    static func redactedJSON(_ data: Data) -> Data? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let redacted = redact(object, key: nil)
        return try? JSONSerialization.data(
            withJSONObject: redacted,
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    static func redact(_ value: Any, key: String?) -> Any {
        if let key, isSensitiveKey(key) { return replacement }
        if key?.lowercased() == "args", let arguments = value as? [String] {
            return sanitizedArguments(arguments)
        }
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { result, item in
                result[item.key] = redact(item.value, key: item.key)
            }
        }
        if let array = value as? [Any] { return array.map { redact($0, key: nil) } }
        if let string = value as? String { return redactSensitiveString(string) }
        return value
    }

    static func sanitizedMCPServer(_ value: Any) -> [String: Any]? {
        guard var server = value as? [String: Any] else { return nil }
        var inherited = (server["env_vars"] as? [String])
            ?? (server["envVars"] as? [String])
            ?? []
        if let environment = server["env"] as? [String: Any] {
            inherited.append(contentsOf: environment.keys)
        }
        for key in server.keys where isSensitiveKey(key) || key.lowercased().contains("header") {
            server.removeValue(forKey: key)
        }
        server.removeValue(forKey: "envVars")
        server.removeValue(forKey: "env_vars")
        if let rawURL = server["url"] as? String {
            server["url"] = sanitizedURL(rawURL)
        }
        if let arguments = server["args"] as? [String] {
            server["args"] = sanitizedArguments(arguments)
        }
        for (key, value) in server where key != "url" && key != "args" {
            server[key] = redact(value, key: key)
        }
        if !inherited.isEmpty {
            server["env_vars"] = Array(Set(inherited)).sorted()
        }
        return server
    }

    static func jsonObject(_ file: URL, sourceRoot: URL) -> [String: Any]? {
        guard let data = AgentImportFileSystem.readData(file, inside: sourceRoot),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object
    }

    private static func isSensitiveKey(_ key: String) -> Bool {
        let compact = key.lowercased().filter(\.isLetter)
        return compact == "env"
            || compact == "environment"
            || compact.contains("secret")
            || compact.contains("token")
            || compact.contains("password")
            || compact.contains("apikey")
            || compact.contains("accesskey")
            || compact.contains("privatekey")
            || compact.contains("authorization")
            || compact.contains("credential")
            || compact.contains("cookie")
    }

    private static func redactSensitiveString(_ value: String) -> String {
        let normalized = value.lowercased()
        let markers = [
            "bearer ", "authorization:", "api_key=", "api-key=", "apikey=",
            "access_key=", "access-key=", "token=", "password=", "client_secret=",
            "private_key=", "-----begin private key", "-----begin rsa private key"
        ]
        let prefixes = ["sk-", "ghp_", "github_pat_", "xoxb-", "xoxp-", "aiza"]
        guard markers.contains(where: normalized.contains)
                || prefixes.contains(where: normalized.contains)
        else { return value }
        return replacement
    }

    private static func sanitizedURL(_ rawValue: String) -> String {
        guard var components = URLComponents(string: rawValue) else {
            return redactSensitiveString(rawValue)
        }
        components.user = nil
        components.password = nil
        components.fragment = nil
        components.queryItems = components.queryItems?.compactMap { item in
            isSensitiveKey(item.name) ? nil : item
        }
        return components.string ?? redactSensitiveString(rawValue)
    }

    private static func sanitizedArguments(_ arguments: [String]) -> [String] {
        var redactNext = false
        return arguments.map { argument in
            if redactNext {
                redactNext = false
                return replacement
            }
            let normalized = argument.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let isCredentialFlag = ["token", "secret", "password", "api-key", "api_key", "apikey"]
                .contains { normalized == "--\($0)" || normalized == "-\($0)" }
            if isCredentialFlag {
                redactNext = true
                return argument
            }
            return redactSensitiveString(argument)
        }
    }
}
