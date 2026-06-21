import Foundation
import QuillCodeCore

public enum ConfigStoreError: Error, CustomStringConvertible {
    case invalidLine(String)

    public var description: String {
        switch self {
        case .invalidLine(let line):
            return "Invalid config line: \(line)"
        }
    }
}

public struct ConfigStore: Sendable {
    public var fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> AppConfig {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return AppConfig()
        }
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        var config = AppConfig()
        var explicitAuthMode: TrustedRouterAuthMode?
        var legacyDeveloperOverrideEnabled: Bool?
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let parts = line.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2 else { throw ConfigStoreError.invalidLine(rawLine) }
            let key = parts[0]
            let value = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            switch key {
            case "default_model":
                config.defaultModel = value
            case "mode":
                config.mode = AgentMode(rawValue: value) ?? config.mode
            case "api_base_url":
                config.apiBaseURL = value
            case "auth_mode":
                explicitAuthMode = TrustedRouterAuthMode(rawValue: value) ?? config.authMode
            case "developer_override_enabled":
                legacyDeveloperOverrideEnabled = (value == "true")
            default:
                continue
            }
        }
        if let explicitAuthMode {
            config.authMode = explicitAuthMode
            config.developerOverrideEnabled = explicitAuthMode == .developerOverride
        } else if legacyDeveloperOverrideEnabled == true {
            config.authMode = .developerOverride
            config.developerOverrideEnabled = true
        }
        return config
    }

    public func save(_ config: AppConfig) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let body = """
        default_model = "\(config.defaultModel)"
        mode = "\(config.mode.rawValue)"
        api_base_url = "\(config.apiBaseURL)"
        auth_mode = "\(config.authMode.rawValue)"
        developer_override_enabled = \(config.developerOverrideEnabled ? "true" : "false")
        """
        try body.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
