import Foundation
import QuillCodeApp
import QuillCodeCore

@MainActor
extension QuillCodeDesktopController {
    func setMode(_ mode: AgentMode) {
        settingsCoordinator.setMode(mode, on: model)
        refresh()
    }

    func setModel(_ modelID: String) {
        settingsCoordinator.setModel(modelID, on: model)
        refresh()
    }

    func toggleModelFavorite(_ modelID: String) {
        settingsCoordinator.toggleModelFavorite(modelID, on: model)
        refresh()
    }

    func saveKeyboardShortcuts(_ preferences: KeyboardShortcutPreferences) {
        settingsCoordinator.setKeyboardShortcutPreferences(preferences, on: model)
        refresh()
    }

    func refreshModelCatalog() async {
        await settingsCoordinator.refreshModelCatalog(on: model)
        refresh()
    }

    func saveSettings(_ update: WorkspaceSettingsUpdate) {
        let accountIdentityChanged = update.changesTrustedRouterAccountIdentity(
            comparedTo: model.root.config
        )
        if accountIdentityChanged {
            model.setTrustedRouterCredits(.unavailable)
        }
        settingsCoordinator.saveSettings(
            update,
            to: model,
            refresh: { [weak self] in self?.refresh() }
        )
        if accountIdentityChanged {
            refreshTrustedRouterCredits()
        }
    }

    func startTrustedRouterSignIn() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await signInCoordinator.completeSignInAndApply(
                to: model,
                settingsCoordinator: settingsCoordinator,
                refresh: { [weak self] in self?.refresh() }
            )
            model.setTrustedRouterCredits(.unavailable)
            refreshTrustedRouterCredits()
        }
    }

    func openComputerUseSystemSettings(_ destination: MacSystemSettingsOpener.Destination) {
        computerUseCoordinator.openSystemSettings(destination, model: model)
        refresh()
    }
}
