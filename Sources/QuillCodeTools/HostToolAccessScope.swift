import Foundation
import QuillCodeCore

/// Path reach available to built-in file tools and shell working directories for one agent run.
///
/// Relative paths always resolve from the selected workspace. `unrestricted` additionally accepts
/// absolute paths and relative traversal outside that workspace. It does not alter review policy,
/// edit guards, output bounds, or provider-owned tools.
public enum HostToolAccessScope: Sendable, Hashable {
    case workspaceOnly
    case unrestricted

    var allowsPathsOutsideWorkspace: Bool {
        self == .unrestricted
    }

    /// Keep the model-facing schema honest when a caller deliberately disables the workspace
    /// filesystem boundary. Only built-in path-bearing tools are adapted; MCP and extension schemas
    /// remain owned by their providers.
    public func adapting(_ definitions: [ToolDefinition]) -> [ToolDefinition] {
        guard self == .unrestricted else { return definitions }
        return definitions.map(Self.unrestrictedDefinition)
    }

    private static func unrestrictedDefinition(_ definition: ToolDefinition) -> ToolDefinition {
        var adapted = definition
        switch definition.name {
        case ToolDefinition.shellRun.name:
            adapted.description = """
            Run a shell command on the host. Relative cwd values start in the current project; \
            absolute or escaping cwd values are allowed.
            """
            adapted.parametersJSON = schema(
                definition.parametersJSON,
                property: "cwd",
                description: """
                Optional working directory. Relative paths start at the current project; absolute \
                and escaping paths are allowed.
                """
            )
        case ToolDefinition.fileRead.name:
            adapted.description = definition.description.replacingOccurrences(
                of: "inside the project workspace",
                with: "on the host filesystem"
            )
            adapted.parametersJSON = pathSchema(definition.parametersJSON)
        case ToolDefinition.fileList.name:
            adapted.description = definition.description.replacingOccurrences(
                of: "inside a workspace directory",
                with: "in a host filesystem directory"
            )
            adapted.parametersJSON = pathSchema(definition.parametersJSON)
        case ToolDefinition.fileSearch.name:
            adapted.description = definition.description.replacingOccurrences(
                of: "inside the project workspace",
                with: "on the host filesystem"
            )
            adapted.parametersJSON = pathSchema(definition.parametersJSON)
        case ToolDefinition.fileWrite.name:
            adapted.description = "Write a UTF-8 file on the host filesystem."
            adapted.parametersJSON = pathSchema(definition.parametersJSON)
        default:
            break
        }
        return adapted
    }

    private static func pathSchema(_ rawValue: String) -> String {
        schema(
            rawValue,
            property: "path",
            description: """
            Path to use. Relative paths start at the current project; absolute and escaping paths \
            are allowed.
            """
        )
    }

    private static func schema(
        _ rawValue: String,
        property: String,
        description: String
    ) -> String {
        guard let data = rawValue.data(using: .utf8),
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var properties = object["properties"] as? [String: Any],
              var field = properties[property] as? [String: Any]
        else {
            return rawValue
        }
        field["description"] = description
        properties[property] = field
        object["properties"] = properties
        guard let encoded = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return rawValue
        }
        return String(decoding: encoded, as: UTF8.self)
    }
}
