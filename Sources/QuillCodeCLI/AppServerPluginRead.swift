import Foundation
import QuillCodeTools

extension AppServerSession {
    func readPlugin(_ value: CLIJSONValue) throws -> CLIJSONValue {
        let params = try AppServerParams(value)
        let marketplacePath = try params.optionalString("marketplacePath")
        let remoteMarketplaceName = try params.optionalString("remoteMarketplaceName")
        let requestedPluginName = try params.requiredString("pluginName")
        guard let pluginName = normalizedPluginIdentifier(requestedPluginName) else {
            throw AppServerRPCError.invalidRequest("pluginName must be a bounded identifier")
        }

        guard (marketplacePath == nil) != (remoteMarketplaceName == nil) else {
            throw AppServerRPCError.invalidRequest(
                "plugin/read requires exactly one of marketplacePath or remoteMarketplaceName"
            )
        }
        if let remoteMarketplaceName {
            guard isBoundedPluginText(remoteMarketplaceName) else {
                throw AppServerRPCError.invalidRequest("invalid remote plugin identifier")
            }
            throw AppServerRPCError.invalidRequest(
                "remote plugin read is not available for marketplace \(remoteMarketplaceName)"
            )
        }

        guard let path = marketplacePath,
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
            throw AppServerRPCError.invalidRequest(
                "failed to read plugin details: \(error.message)"
            )
        }
        guard let marketplace = discovery.marketplaces.first,
              let entry = marketplace.plugins.first(where: { $0.name == pluginName })
        else {
            throw AppServerRPCError.invalidRequest("plugin `\(pluginName)` was not found")
        }
        guard entry.package != nil,
              let detail = CodexPluginPackageDetailLoader.load(
                at: entry.source.localPath,
                pluginIdentifier: "\(entry.name)@\(marketplace.name)"
              )
        else {
            throw AppServerRPCError.invalidRequest(
                "plugin `\(pluginName)` has a missing or invalid plugin.json"
            )
        }

        let marketplaceRoot = CodexPluginMarketplaceCatalogLoader.marketplaceRoot(
            for: marketplace.path
        )
        let roots = [paths.home, marketplaceRoot].compactMap { $0 }
        let installed = AppServerInstalledPluginStateLoader.load(
            roots: roots,
            quillCodeHome: paths.home
        )
        let row = AppServerPluginRow(
            entry: entry,
            installedState: installed[entry.name]
        )
        return .object(["plugin": pluginDetailValue(
            marketplace: marketplace,
            row: row,
            detail: detail
        )])
    }

    func readRemotePluginSkill(_ value: CLIJSONValue) throws -> CLIJSONValue {
        let params = try AppServerParams(value)
        let marketplace = try params.requiredString("remoteMarketplaceName")
        let pluginID = try params.requiredString("remotePluginId")
        let skillName = try params.requiredString("skillName")
        guard [marketplace, pluginID, skillName].allSatisfy(isBoundedPluginText) else {
            throw AppServerRPCError.invalidRequest("invalid remote plugin skill identifier")
        }
        throw AppServerRPCError.invalidRequest(
            "remote plugin skill read is not available for marketplace \(marketplace)"
        )
    }

    private func pluginDetailValue(
        marketplace: CodexPluginMarketplaceCatalog,
        row: AppServerPluginRow,
        detail: CodexPluginPackageDetail
    ) -> CLIJSONValue {
        .object([
            "marketplaceName": .string(marketplace.name),
            "marketplacePath": .string(marketplace.path.standardizedFileURL.path),
            "summary": pluginSummaryValue(row, marketplaceName: marketplace.name),
            "shareUrl": .null,
            "description": pluginOptionalString(row.entry.package?.description),
            "skills": .array(detail.skills.map {
                pluginSkillValue($0, pluginName: row.entry.name)
            }),
            "hooks": .array(detail.hooks.map { hook in
                .object([
                    "key": .string(hook.key),
                    "eventName": .string(hook.event.rawValue)
                ])
            }),
            "apps": .array(detail.apps.map { app in
                .object([
                    "id": .string(app.id),
                    "name": .string(app.name),
                    "description": .null,
                    "installUrl": .null,
                    "category": pluginOptionalString(app.category)
                ])
            }),
            "appTemplates": .array([]),
            "mcpServers": .array(detail.mcpServerNames.map(CLIJSONValue.string))
        ])
    }

    private func pluginSkillValue(
        _ skill: SkillCatalogMetadata,
        pluginName: String
    ) -> CLIJSONValue {
        let namespacedName = "\(pluginName):\(skill.name)"
        return .object([
            "name": .string(namespacedName),
            "description": .string(skill.description),
            "shortDescription": pluginOptionalString(skill.shortDescription),
            "interface": skill.interface.map(pluginSkillInterfaceValue) ?? .null,
            "path": .string(skill.path.standardizedFileURL.path),
            "enabled": .bool(appConfig.skillConfiguration.isEnabled(
                name: namespacedName,
                manifestPath: skill.path
            ))
        ])
    }

    private func pluginSkillInterfaceValue(_ interface: SkillInterfaceMetadata) -> CLIJSONValue {
        var value: [String: CLIJSONValue] = [:]
        if let displayName = interface.displayName { value["displayName"] = .string(displayName) }
        if let shortDescription = interface.shortDescription {
            value["shortDescription"] = .string(shortDescription)
        }
        if let iconSmall = interface.iconSmall {
            value["iconSmall"] = .string(iconSmall.standardizedFileURL.path)
        }
        if let iconLarge = interface.iconLarge {
            value["iconLarge"] = .string(iconLarge.standardizedFileURL.path)
        }
        if let brandColor = interface.brandColor { value["brandColor"] = .string(brandColor) }
        if let defaultPrompt = interface.defaultPrompt { value["defaultPrompt"] = .string(defaultPrompt) }
        return .object(value)
    }

    private func isBoundedPluginText(_ value: String) -> Bool {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !value.isEmpty && value.utf8.count <= 4_096 && !value.contains("\0")
    }
}
