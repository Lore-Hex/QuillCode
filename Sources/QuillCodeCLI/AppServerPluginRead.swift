import Foundation
import QuillCodeCore
import QuillCodeTools

extension AppServerSession {
    private static let maximumPluginSkillBodyBytes = 48_000

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

    func readPluginSkill(_ value: CLIJSONValue) throws -> CLIJSONValue {
        let params = try AppServerParams(value)
        let marketplacePath = try params.optionalString("marketplacePath")
        let remoteMarketplaceName = try params.optionalString("remoteMarketplaceName")
        let pluginName = try params.optionalString("pluginName")
        let pluginID = try params.optionalString("remotePluginId")
        let skillName = try params.requiredString("skillName")
        guard (marketplacePath == nil) != (remoteMarketplaceName == nil) else {
            throw AppServerRPCError.invalidRequest(
                "plugin/skill/read requires exactly one of marketplacePath or remoteMarketplaceName"
            )
        }

        if let remoteMarketplaceName {
            let remotePluginID = pluginID ?? pluginName ?? ""
            let values = [remoteMarketplaceName, remotePluginID, skillName]
            guard values.allSatisfy(isBoundedPluginText) else {
                throw AppServerRPCError.invalidRequest("invalid remote plugin skill identifier")
            }
            throw AppServerRPCError.invalidRequest(
                "remote plugin skill read is not available for marketplace \(remoteMarketplaceName)"
            )
        }

        guard let marketplacePath else {
            throw AppServerRPCError.invalidRequest("marketplacePath is required for local plugin skill reads")
        }
        guard pluginID == nil else {
            throw AppServerRPCError.invalidRequest("invalid remote plugin skill identifier")
        }
        guard let pluginName, let normalizedPluginName = normalizedPluginIdentifier(pluginName) else {
            throw AppServerRPCError.invalidRequest("pluginName must be a bounded identifier")
        }

        let selection = try localPluginSelection(
            AppServerPluginSourceRequest(
                marketplacePath: marketplacePath,
                remoteMarketplaceName: nil,
                pluginName: normalizedPluginName
            ),
            operation: "read plugin skill"
        )
        return try readLocalPluginSkill(
            marketplace: selection.marketplace,
            entry: selection.entry,
            requestedSkillName: skillName
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

    private func readLocalPluginSkill(
        marketplace: CodexPluginMarketplaceCatalog,
        entry: CodexPluginMarketplaceEntry,
        requestedSkillName: String
    ) throws -> CLIJSONValue {
        guard entry.package != nil,
              let detail = CodexPluginPackageDetailLoader.load(
                at: entry.source.localPath,
                pluginIdentifier: "\(entry.name)@\(marketplace.name)"
              )
        else {
            throw AppServerRPCError.invalidRequest(
                "plugin `\(entry.name)` has a missing or invalid plugin.json"
            )
        }

        let skillName = try normalizedSkillName(requestedSkillName, pluginName: entry.name)
        guard let skill = detail.skills.first(where: { $0.name == skillName }) else {
            throw AppServerRPCError.invalidRequest(
                "skill `\(requestedSkillName)` was not found in plugin `\(entry.name)`"
            )
        }

        let pluginRoot = entry.source.localPath.standardizedFileURL.resolvingSymlinksInPath()
        let skillFile = skill.path.standardizedFileURL.resolvingSymlinksInPath()
        guard WorkspaceBoundary.isWithin(skillFile, root: pluginRoot) else {
            throw AppServerRPCError.invalidRequest("plugin skill path escapes plugin package")
        }

        let contents = try boundedPluginSkillContent(at: skillFile)
        let namespacedName = "\(entry.name):\(skill.name)"
        return .object([
            "skill": .object([
                "marketplaceName": .string(marketplace.name),
                "marketplacePath": .string(marketplace.path.standardizedFileURL.path),
                "pluginName": .string(entry.name),
                "name": .string(namespacedName),
                "skillName": .string(skill.name),
                "description": .string(skill.description),
                "shortDescription": pluginOptionalString(skill.shortDescription),
                "interface": skill.interface.map(pluginSkillInterfaceValue) ?? .null,
                "path": .string(skillFile.path),
                "content": .string(contents),
                "truncated": .bool(false),
                "enabled": .bool(appConfig.skillConfiguration.isEnabled(
                    name: namespacedName,
                    manifestPath: skill.path
                ))
            ])
        ])
    }

    private func normalizedSkillName(_ value: String, pluginName: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawSkillName: String
        if trimmed.hasPrefix("\(pluginName):") {
            rawSkillName = String(trimmed.dropFirst(pluginName.count + 1))
        } else {
            rawSkillName = trimmed
        }
        guard SkillResolver.isSafeSkillName(rawSkillName),
              rawSkillName.count <= 64
        else {
            throw AppServerRPCError.invalidRequest("skillName must be a bounded skill identifier")
        }
        return rawSkillName
    }

    private func boundedPluginSkillContent(at url: URL) throws -> String {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        } catch {
            throw AppServerRPCError.invalidRequest(
                "plugin skill manifest is unreadable: \(error.localizedDescription)"
            )
        }
        guard values.isRegularFile == true else {
            throw AppServerRPCError.invalidRequest("plugin skill manifest is not a regular file")
        }

        guard (values.fileSize ?? Self.maximumPluginSkillBodyBytes + 1)
            <= Self.maximumPluginSkillBodyBytes
        else {
            throw AppServerRPCError.invalidRequest(
                "plugin skill manifest exceeds \(Self.maximumPluginSkillBodyBytes) bytes"
            )
        }
        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw AppServerRPCError.invalidRequest(
                "plugin skill manifest is unreadable: \(error.localizedDescription)"
            )
        }
        guard data.count <= Self.maximumPluginSkillBodyBytes else {
            throw AppServerRPCError.invalidRequest(
                "plugin skill manifest exceeds \(Self.maximumPluginSkillBodyBytes) bytes"
            )
        }
        guard let contents = String(data: data, encoding: .utf8) else {
            throw AppServerRPCError.invalidRequest("plugin skill manifest is not UTF-8")
        }
        return contents
    }

}
