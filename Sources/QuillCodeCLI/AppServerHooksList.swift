import Foundation
import QuillCodeCore
import QuillCodeHooks
import QuillCodePersistence
import QuillCodeTools

extension AppServerSession {
    private static let maximumHookCWDs = 32
    private static let maximumHookCWDBytes = 4_096

    func listHooks(_ value: CLIJSONValue) throws -> CLIJSONValue {
        let params = try AppServerParams(value)
        let requested = try params.optionalArray("cwds") ?? []
        guard requested.count <= Self.maximumHookCWDs else {
            throw AppServerRPCError.invalidParams(
                "cwds cannot contain more than \(Self.maximumHookCWDs) entries"
            )
        }
        let cwds = requested.isEmpty
            ? [currentDirectory]
            : try requested.enumerated().map { index, value in
                guard let path = value.stringValue,
                      !path.isEmpty,
                      path.utf8.count <= Self.maximumHookCWDBytes,
                      NSString(string: path).isAbsolutePath
                else {
                    throw AppServerRPCError.invalidParams(
                        "cwds[\(index)] must be a bounded absolute path"
                    )
                }
                return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
            }

        let global = GlobalHookConfigurationLoader.load(from: paths.hookConfigurationPaths)
        let globalTrust = ProjectHookTrustFileStore(directory: paths.hookTrustDirectory)
            .load(forWorkspaceRoot: paths.home)
        let installedPluginMarketplaces = CodexInstalledPluginStore.marketplaceDirectories(
            in: paths.home
        )
        let userPlugins = CodexPluginHookConfigurationLoader.discover(
            packageDirectories: [
                paths.home.appendingPathComponent("plugins", isDirectory: true)
            ] + installedPluginMarketplaces,
            scopeRoot: paths.home,
            trustScope: .user
        )
        return .object([
            "data": .array(cwds.map { cwd in
                hookListEntry(
                    cwd: cwd,
                    global: global,
                    globalTrust: globalTrust,
                    userPlugins: userPlugins
                )
            })
        ])
    }

    private func hookListEntry(
        cwd: URL,
        global: WorkspaceGlobalHookConfiguration,
        globalTrust: ProjectHookTrustLoadResult,
        userPlugins: PluginHookCatalogDiscovery
    ) -> CLIJSONValue {
        let cwd = cwd.standardizedFileURL.resolvingSymlinksInPath()
        guard isDirectory(cwd) else {
            return hookListEntry(
                cwd: cwd,
                hooks: [],
                warnings: [],
                errors: [HookConfigurationDiagnostic(
                    path: cwd.path,
                    message: "cwd does not name an existing directory"
                )]
            )
        }

        let configurationRoot = GitRepositoryRootResolver.resolve(containing: cwd)?.configuration
            ?? cwd
        let project = ProjectHookConfigurationLoader.discover(from: configurationRoot)
        let hooksEnabled = global.hooksFeatureIsManaged
            ? global.hooksEnabled
            : project.hooksFeatureOverride ?? global.hooksEnabled
        let managedOnly = global.managedOnly || project.allowManagedHooksOnly == true
        let projectTrust = ProjectHookTrustFileStore(directory: paths.hookTrustDirectory)
            .load(forWorkspaceRoot: configurationRoot)
        let projectPlugins = managedOnly
            ? PluginHookCatalogDiscovery()
            : CodexPluginHookConfigurationLoader.discover(
                packageDirectories: [
                    configurationRoot.appendingPathComponent(".quillcode/plugins", isDirectory: true),
                    configurationRoot.appendingPathComponent(".codex/plugins", isDirectory: true)
                ],
                scopeRoot: configurationRoot
            )

        var warnings = managedOnly ? [] : userPlugins.warnings + projectPlugins.warnings
        warnings.append(contentsOf: globalTrust.diagnostics)
        warnings.append(contentsOf: projectTrust.diagnostics)
        let candidateDefinitions = global.definitions
            + (managedOnly ? [] : userPlugins.definitions + project.definitions + projectPlugins.definitions)
        warnings.append(contentsOf: candidateDefinitions.compactMap { definition in
            definition.source == .plugin ? nil : hookSupportWarning(definition)
        })

        let entries: [HookCatalogEntry]
        if hooksEnabled {
            var resolved = HookCatalogResolver.resolve(
                global.definitions + (managedOnly ? [] : userPlugins.definitions),
                states: global.hookStates,
                trust: globalTrust
            )
            if !managedOnly {
                resolved.append(contentsOf: HookCatalogResolver.resolve(
                    project.definitions + projectPlugins.definitions,
                    states: project.hookStates,
                    trust: projectTrust,
                    displayOrderOffset: resolved.count
                ))
            }
            entries = resolved
        } else {
            entries = []
        }

        return hookListEntry(
            cwd: cwd,
            hooks: entries,
            warnings: stableUnique(warnings),
            errors: global.diagnostics + project.diagnostics
        )
    }

    private func hookListEntry(
        cwd: URL,
        hooks: [HookCatalogEntry],
        warnings: [String],
        errors: [HookConfigurationDiagnostic]
    ) -> CLIJSONValue {
        .object([
            "cwd": .string(cwd.path),
            "hooks": .array(hooks.map(hookValue)),
            "warnings": .array(warnings.map(CLIJSONValue.string)),
            "errors": .array(errors.map { error in
                .object([
                    "path": .string(error.path),
                    "message": .string(error.message)
                ])
            })
        ])
    }

    private func hookValue(_ entry: HookCatalogEntry) -> CLIJSONValue {
        let definition = entry.definition
        let hook = definition.hook
        return .object([
            "key": .string(definition.key),
            "eventName": .string(hook.event),
            "handlerType": .string(hook.handlerType),
            "matcher": optionalString(hook.matcher),
            "command": optionalString(hook.command),
            "timeoutSec": .number(Double(hook.timeoutSeconds)),
            "statusMessage": optionalString(hook.statusMessage),
            "sourcePath": .string(definition.sourcePath.standardizedFileURL.path),
            "source": .string(definition.source.rawValue),
            "pluginId": optionalString(definition.pluginID),
            "displayOrder": .number(Double(entry.displayOrder)),
            "enabled": .bool(entry.enabled),
            "isManaged": .bool(entry.isManaged),
            "currentHash": .string(hook.definitionHash),
            "trustStatus": .string(entry.trustStatus.rawValue)
        ])
    }

    private func hookSupportWarning(_ definition: HookCatalogDefinition) -> String? {
        guard !definition.hook.supportStatus.isSupported else { return nil }
        return "ignored unsupported hook \(definition.key): "
            + definition.hook.supportStatus.rawValue
    }

    private func stableUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private func optionalString(_ value: String?) -> CLIJSONValue {
        value.map(CLIJSONValue.string) ?? .null
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }
}
