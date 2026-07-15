import QuillCodeCore
import QuillCodePersistence

enum ProjectPluginHookResolver {
    static func resolve(
        _ hooks: [ProjectPluginHook],
        trust: ProjectHookTrustLoadResult
    ) -> [ProjectPluginHook] {
        hooks.map { hook in
            var resolved = hook
            resolved.trustStatus = trust.status(for: hook)
            return resolved
        }
    }

    static func executableRunHooks(from hooks: [ProjectPluginHook]) -> [ProjectRunHook] {
        hooks.compactMap { hook in
            guard hook.isExecutable,
                  let timing = timing(for: hook.event),
                  let command = hook.command
            else { return nil }
            return ProjectRunHook(
                id: hook.id,
                timing: timing,
                title: hook.statusMessage ?? "\(hook.pluginName) · \(hook.event)",
                detail: "Trusted hook from \(hook.pluginName).",
                relativePath: hook.relativePath,
                command: command,
                timeoutSeconds: hook.timeoutSeconds,
                pluginID: hook.pluginID,
                pluginRootRelativePath: hook.pluginRootRelativePath,
                trustScope: hook.effectiveTrustScope
            )
        }
    }

    private static func timing(for event: String) -> ProjectRunHookTiming? {
        switch event {
        case "UserPromptSubmit": return .beforeAgentRun
        case "Stop": return .afterAgentRun
        default: return nil
        }
    }
}
