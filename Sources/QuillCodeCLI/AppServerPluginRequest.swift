import Foundation
import QuillCodeTools

struct AppServerPluginSourceRequest: Sendable {
    var marketplacePath: String?
    var remoteMarketplaceName: String?
    var pluginName: String
}

struct AppServerLocalPluginSelection: Sendable {
    var marketplace: CodexPluginMarketplaceCatalog
    var entry: CodexPluginMarketplaceEntry
}

extension AppServerSession {
    func pluginSourceRequest(
        _ value: CLIJSONValue,
        method: String
    ) throws -> AppServerPluginSourceRequest {
        let params = try AppServerParams(value)
        let marketplacePath = try params.optionalString("marketplacePath")
        let remoteMarketplaceName = try params.optionalString("remoteMarketplaceName")
        let requestedPluginName = try params.requiredString("pluginName")
        guard let pluginName = normalizedPluginIdentifier(requestedPluginName) else {
            throw AppServerRPCError.invalidRequest("pluginName must be a bounded identifier")
        }
        guard (marketplacePath == nil) != (remoteMarketplaceName == nil) else {
            throw AppServerRPCError.invalidRequest(
                "\(method) requires exactly one of marketplacePath or remoteMarketplaceName"
            )
        }
        if let remoteMarketplaceName, !isBoundedPluginText(remoteMarketplaceName) {
            throw AppServerRPCError.invalidRequest("invalid remote plugin identifier")
        }
        return AppServerPluginSourceRequest(
            marketplacePath: marketplacePath,
            remoteMarketplaceName: remoteMarketplaceName,
            pluginName: pluginName
        )
    }

    func localPluginSelection(
        _ request: AppServerPluginSourceRequest,
        operation: String
    ) throws -> AppServerLocalPluginSelection {
        guard let path = request.marketplacePath,
              path.utf8.count <= Self.maximumPluginPathBytes,
              NSString(string: path).isAbsolutePath
        else {
            throw AppServerRPCError.invalidRequest(
                "marketplacePath must be a bounded absolute path and pluginName a bounded identifier"
            )
        }
        let pathURL = URL(fileURLWithPath: path, isDirectory: false).standardizedFileURL
        let discovery = CodexPluginMarketplaceCatalogLoader.load(at: pathURL)
        if let error = discovery.errors.first {
            throw AppServerRPCError.invalidRequest("failed to \(operation) plugin: \(error.message)")
        }
        guard let marketplace = discovery.marketplaces.first,
              let entry = marketplace.plugins.first(where: { $0.name == request.pluginName })
        else {
            throw AppServerRPCError.invalidRequest(
                "plugin `\(request.pluginName)` was not found"
            )
        }
        return AppServerLocalPluginSelection(marketplace: marketplace, entry: entry)
    }

    func isBoundedPluginText(_ value: String) -> Bool {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !value.isEmpty && value.utf8.count <= 4_096 && !value.contains("\0")
    }
}
