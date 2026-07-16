import Foundation
import QuillCodeTools

extension AppServerSession {
    func installPlugin(_ value: CLIJSONValue) async throws -> CLIJSONValue {
        let request = try pluginSourceRequest(value, method: "plugin/install")
        if let remoteMarketplaceName = request.remoteMarketplaceName {
            throw AppServerRPCError.invalidRequest(
                "remote plugin install is not available for marketplace \(remoteMarketplaceName)"
            )
        }

        let selection = try localPluginSelection(request, operation: "install")
        guard selection.entry.installPolicy != .notAvailable else {
            throw AppServerRPCError.invalidRequest(
                "plugin `\(request.pluginName)` is not available for install"
            )
        }
        guard selection.entry.package != nil,
              let detail = CodexPluginPackageDetailLoader.load(
                at: selection.entry.source.localPath,
                pluginIdentifier: "\(selection.entry.name)@\(selection.marketplace.name)"
              )
        else {
            throw AppServerRPCError.invalidRequest(
                "plugin `\(request.pluginName)` has a missing or invalid plugin.json"
            )
        }

        do {
            _ = try CodexInstalledPluginStore(home: paths.home).install(
                source: selection.entry.source.localPath,
                pluginName: selection.entry.name,
                marketplaceName: selection.marketplace.name
            )
        } catch {
            throw AppServerRPCError.invalidRequest("failed to install plugin: \(error)")
        }
        await pluginMutationDidChangeSkills()

        return .object([
            "authPolicy": .string(selection.entry.authPolicy.rawValue),
            "appsNeedingAuth": .array(detail.apps.map { app in
                .object([
                    "id": .string(app.id),
                    "name": .string(app.name),
                    "description": .null,
                    "installUrl": .null,
                    "category": app.category.map(CLIJSONValue.string) ?? .null
                ])
            })
        ])
    }

    func uninstallPlugin(_ value: CLIJSONValue) async throws -> CLIJSONValue {
        let params = try AppServerParams(value)
        let pluginID = try params.requiredString("pluginId")
        guard pluginID.utf8.count <= 257, !pluginID.contains("\0") else {
            throw AppServerRPCError.invalidRequest("invalid plugin id")
        }
        do {
            try CodexInstalledPluginStore(home: paths.home).uninstall(pluginID: pluginID)
        } catch {
            throw AppServerRPCError.invalidRequest("failed to uninstall plugin: \(error)")
        }
        await pluginMutationDidChangeSkills()
        return .object([:])
    }

    private func pluginMutationDidChangeSkills() async {
        cachedSkillSnapshots.removeAll(keepingCapacity: true)
        refreshSkillWatcher()
        await sendNotification("skills/changed", params: .object([:]))
    }
}
