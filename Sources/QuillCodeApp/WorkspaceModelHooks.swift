import Foundation
import QuillCodeCore

@MainActor
extension QuillCodeWorkspaceModel {
    func refreshGlobalHookConfiguration() {
        guard let hookConfigurationPaths,
              let projectHookTrustStore,
              let globalHookTrustScope
        else { return }
        globalHookConfiguration = GlobalHookConfigurationLoader
            .load(from: hookConfigurationPaths)
            .resolvingTrust(
                projectHookTrustStore.load(forWorkspaceRoot: globalHookTrustScope)
            )
    }

    func effectiveHookDefinitions(for project: ProjectRef?) -> [ProjectPluginHook] {
        guard globalHookConfiguration.hooksEnabled else { return [] }
        if globalHookConfiguration.managedOnly {
            return globalHookConfiguration.hooks
        }
        return globalHookConfiguration.hooks + (project?.pluginHooks ?? [])
    }

    func effectiveRunHooks(for project: ProjectRef?) -> [ProjectRunHook] {
        guard globalHookConfiguration.hooksEnabled else { return [] }
        let global = ProjectPluginHookResolver.executableRunHooks(
            from: globalHookConfiguration.hooks
        )
        return globalHookConfiguration.managedOnly
            ? global
            : global + (project?.runHooks ?? [])
    }

    func trustScopeRoot(for hook: ProjectPluginHook, project: ProjectRef?) -> URL? {
        switch hook.effectiveTrustScope {
        case .managed:
            return nil
        case .user:
            return globalHookTrustScope
        case .workspace:
            guard let project, !project.isRemote else { return nil }
            return URL(fileURLWithPath: project.path)
        }
    }
}
