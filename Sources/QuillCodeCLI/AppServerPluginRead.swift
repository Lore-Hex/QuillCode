import Foundation
import QuillCodeTools

extension AppServerSession {
    func readPlugin(_ value: CLIJSONValue) throws -> CLIJSONValue {
        let request = try pluginSourceRequest(value, method: "plugin/read")
        if let remoteMarketplaceName = request.remoteMarketplaceName {
            throw AppServerRPCError.invalidRequest(
                "remote plugin read is not available for marketplace \(remoteMarketplaceName)"
            )
        }
        let selection = try localPluginSelection(request, operation: "read")
        let marketplace = selection.marketplace
        let entry = selection.entry
        guard entry.package != nil,
              let detail = CodexPluginPackageDetailLoader.load(
                at: entry.source.localPath,
                pluginIdentifier: "\(entry.name)@\(marketplace.name)"
              )
        else {
            throw AppServerRPCError.invalidRequest(
                "plugin `\(request.pluginName)` has a missing or invalid plugin.json"
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

}
