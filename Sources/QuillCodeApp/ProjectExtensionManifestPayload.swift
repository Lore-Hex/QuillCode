import Foundation
import QuillCodeCore

struct ProjectExtensionManifestPayload: Decodable {
    var id: String?
    var kind: String?
    var name: String?
    var description: String?
    var summary: String?
    var version: String?
    var source: String?
    var homepage: String?
    var enabled: Bool?
    var command: String?
    var args: [String]?
    var transport: String?
    var installCommand: String?
    var installTimeoutSeconds: Int?
    var updateCommand: String?
    var updateTimeoutSeconds: Int?

    var normalizedID: String {
        (id ?? name ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-" }
    }

    var marketplaceKind: ProjectExtensionKind? {
        guard let kind = normalizedOptional(kind, maxLength: 80)?
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        else {
            return nil
        }

        switch kind {
        case "plugin", "plugins":
            return .plugin
        case "skill", "skills":
            return .skill
        case "mcp", "mcp_server", "mcpserver", "mcp_servers", "mcpservers":
            return .mcpServer
        default:
            return nil
        }
    }

    var displayName: String? {
        normalizedOptional(name, maxLength: 120)
    }

    var summaryText: String {
        let text = summary ?? description ?? ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var versionText: String? {
        normalizedOptional(version, maxLength: 80)
    }

    var sourceText: String? {
        normalizedOptional(source ?? homepage, maxLength: 500)
    }

    var updateCommandText: String? {
        normalizedOptional(updateCommand, maxLength: 1_200)
    }

    var installCommandText: String? {
        normalizedOptional(installCommand, maxLength: 1_200)
    }

    var updateTimeout: Int? {
        boundedTimeout(updateTimeoutSeconds)
    }

    var installTimeout: Int? {
        boundedTimeout(installTimeoutSeconds)
    }

    var launchCommand: String? {
        guard let command = launchExecutable else { return nil }
        let args = normalizedArgs
        return args.isEmpty ? command : ([command] + args).joined(separator: " ")
    }

    var launchExecutable: String? {
        normalizedOptional(command, maxLength: 1_200)
    }

    var launchArguments: [String]? {
        normalizedArgs.isEmpty ? nil : normalizedArgs
    }

    func transportKind(for kind: ProjectExtensionKind) -> ProjectExtensionTransport? {
        if let transport = normalizedOptional(transport, maxLength: 80)?.lowercased(),
           let parsed = ProjectExtensionTransport(rawValue: transport) {
            return parsed
        }
        return kind == .mcpServer && launchCommand != nil ? .stdio : nil
    }

    private var normalizedArgs: [String] {
        (args ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func boundedTimeout(_ seconds: Int?) -> Int? {
        guard let seconds else { return nil }
        return min(max(seconds, 5), 1_800)
    }

    private func normalizedOptional(_ value: String?, maxLength: Int) -> String? {
        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty,
              text.count <= maxLength
        else {
            return nil
        }
        return text
    }
}
