import Foundation
import QuillCodeTools

struct AppServerMCPContext: Sendable {
    var scope: String
    var configurations: [String: AppServerMCPServerConfiguration]
}

extension AppServerSession {
    func listMCPServerStatus(_ raw: CLIJSONValue) async throws -> CLIJSONValue {
        let params = try AppServerParams(raw)
        let detail: MCPProbeDetail
        switch try params.optionalString("detail") {
        case nil, "full": detail = .full
        case "toolsAndAuthOnly": detail = .toolsAndAuthOnly
        default: throw AppServerRPCError.invalidParams("detail must be full or toolsAndAuthOnly")
        }
        let limit = try params.optionalInt("limit") ?? 50
        guard (1...100).contains(limit) else {
            throw AppServerRPCError.invalidParams("limit must be between 1 and 100")
        }
        let offset = try Self.mcpCursorOffset(try params.optionalString("cursor"))
        let context = try await mcpContext(threadID: try params.optionalString("threadId"))
        let statuses = await mcpRegistry.statuses(
            scope: context.scope,
            configurations: context.configurations,
            detail: detail
        )
        guard offset <= statuses.count else {
            throw AppServerRPCError.invalidParams("cursor is outside the result set")
        }
        let page = Array(statuses.dropFirst(offset).prefix(limit))
        let nextOffset = offset + page.count
        return .object([
            "data": .array(page.map(mcpStatusValue)),
            "nextCursor": nextOffset < statuses.count
                ? .string(Self.mcpCursor(nextOffset))
                : .null
        ])
    }

    func reloadMCPServers(
        _ raw: CLIJSONValue,
        method: String = "config/mcpServer/reload"
    ) async throws -> CLIJSONValue {
        try AppServerDiscoveryParams.requireEmpty(raw, method: method)
        cancelAllMCPServerStartups()
        await mcpRegistry.reload()
        return .object([:])
    }

    func callMCPServerTool(_ raw: CLIJSONValue) async throws -> CLIJSONValue {
        let params = try AppServerParams(raw)
        let threadID = try params.requiredString("threadId")
        let server = try params.requiredString("server")
        let tool = try params.requiredString("tool")
        let context = try await mcpContext(threadID: threadID)
        guard let configuration = context.configurations[server] else {
            throw AppServerRPCError.invalidRequest("No MCP server named '\(server)' found.")
        }
        do {
            let arguments = try params.object["arguments"].map { try $0.mcpJSONValue }
            let metadata = try params.object["_meta"].map { try $0.mcpJSONValue }
            let result = try await mcpRegistry.callTool(
                scope: context.scope,
                configuration: configuration,
                tool: tool,
                arguments: arguments,
                metadata: metadata
            )
            var response: [String: CLIJSONValue] = [
                "content": .array(result.content.map(\.cliJSONValue))
            ]
            if let structured = result.structuredContent { response["structuredContent"] = structured.cliJSONValue }
            if let isError = result.isError { response["isError"] = .bool(isError) }
            if let metadata = result.metadata { response["_meta"] = metadata.cliJSONValue }
            return .object(response)
        } catch let error as AppServerRPCError {
            throw error
        } catch {
            throw AppServerRPCError.internalError(
                "MCP tool '\(server)/\(tool)' failed: \(error.localizedDescription)"
            )
        }
    }

    func readMCPResource(_ raw: CLIJSONValue) async throws -> CLIJSONValue {
        let params = try AppServerParams(raw)
        let server = try params.requiredString("server")
        let uri = try params.requiredString("uri")
        let context = try await mcpContext(threadID: try params.optionalString("threadId"))
        guard let configuration = context.configurations[server] else {
            throw AppServerRPCError.invalidRequest("No MCP server named '\(server)' found.")
        }
        do {
            let result = try await mcpRegistry.readResource(
                scope: context.scope,
                configuration: configuration,
                uri: uri
            )
            return .object(["contents": .array(result.contents.map(\.cliJSONValue))])
        } catch {
            throw AppServerRPCError.internalError(
                "MCP resource read from '\(server)' failed: \(error.localizedDescription)"
            )
        }
    }

    func mcpContext(threadID: String?) async throws -> AppServerMCPContext {
        let projectRoot: URL?
        let scope: String
        if let threadID {
            guard let id = UUID(uuidString: threadID) else {
                throw AppServerRPCError.invalidRequest("invalid thread id: \(threadID)")
            }
            let record: AppServerThreadRecord
            do {
                record = try await repository.load(id)
            } catch {
                throw AppServerRPCError.invalidRequest("thread not found: \(threadID)")
            }
            projectRoot = record.settings.cwd
            scope = "thread:\(id.uuidString.lowercased())"
        } else {
            projectRoot = nil
            scope = "global"
        }
        return try loadMCPContext(scope: scope, projectRoot: projectRoot)
    }

    func mcpContext(for record: AppServerThreadRecord) throws -> AppServerMCPContext {
        try loadMCPContext(
            scope: "thread:\(record.thread.id.uuidString.lowercased())",
            projectRoot: record.settings.cwd
        )
    }

    private func loadMCPContext(scope: String, projectRoot: URL?) throws -> AppServerMCPContext {
        do {
            let configurations = try AppServerMCPConfigurationLoader.load(
                globalConfig: paths.configFile,
                projectRoot: projectRoot,
                fallbackCWD: projectRoot ?? currentDirectory,
                environment: environment
            )
            return AppServerMCPContext(scope: scope, configurations: configurations)
        } catch let error as AppServerRPCError {
            throw error
        } catch {
            throw AppServerRPCError.internalError("failed to load MCP configuration: \(error.localizedDescription)")
        }
    }

    private func mcpStatusValue(_ status: AppServerMCPServerStatus) -> CLIJSONValue {
        var tools: [String: CLIJSONValue] = [:]
        for rawTool in status.probe?.tools ?? [] {
            guard let name = rawTool.objectValue?["name"]?.stringValue,
                  status.configuration.permitsTool(named: name)
            else { continue }
            tools[name] = rawTool.cliJSONValue
        }
        return .object([
            "name": .string(status.configuration.name),
            "serverInfo": status.probe?.serverInfo?.cliJSONValue ?? .null,
            "tools": .object(tools),
            "resources": .array((status.probe?.resources ?? []).map(\.cliJSONValue)),
            "resourceTemplates": .array((status.probe?.resourceTemplates ?? []).map(\.cliJSONValue)),
            "authStatus": .string(status.configuration.authStatus.rawValue)
        ])
    }

    private static func mcpCursor(_ offset: Int) -> String {
        Data("mcp:\(offset)".utf8).base64EncodedString()
    }

    private static func mcpCursorOffset(_ cursor: String?) throws -> Int {
        guard let cursor else { return 0 }
        guard let data = Data(base64Encoded: cursor),
              let decoded = String(data: data, encoding: .utf8),
              decoded.hasPrefix("mcp:"),
              let offset = Int(decoded.dropFirst(4)),
              offset >= 0
        else { throw AppServerRPCError.invalidParams("cursor is invalid") }
        return offset
    }
}

private extension CLIJSONValue {
    var mcpJSONValue: MCPJSONValue {
        get throws {
            switch self {
            case .object(let value): return .object(try value.mapValues { try $0.mcpJSONValue })
            case .array(let value): return .array(try value.map { try $0.mcpJSONValue })
            case .string(let value): return .string(value)
            case .number(let value):
                guard value.isFinite else { throw AppServerRPCError.invalidParams("MCP JSON numbers must be finite") }
                return .number(value)
            case .bool(let value): return .bool(value)
            case .null: return .null
            }
        }
    }
}

private extension MCPJSONValue {
    var cliJSONValue: CLIJSONValue {
        switch self {
        case .object(let value): .object(value.mapValues(\.cliJSONValue))
        case .array(let value): .array(value.map(\.cliJSONValue))
        case .string(let value): .string(value)
        case .number(let value): .number(value)
        case .bool(let value): .bool(value)
        case .null: .null
        }
    }
}
