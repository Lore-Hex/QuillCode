import Foundation
import QuillCodeApp
import QuillComputerUseKit

protocol QuillCodeDesktopComputerUseSettingsOpening {
    @discardableResult
    func open(_ destination: MacSystemSettingsOpener.Destination) -> Bool
}

extension MacSystemSettingsOpener: QuillCodeDesktopComputerUseSettingsOpening {}

@MainActor
final class QuillCodeDesktopComputerUseCoordinator {
    private var backend: any ComputerUseBackend
    private let systemSettingsOpener: any QuillCodeDesktopComputerUseSettingsOpening
    /// Monotonic token so an in-flight foreground-app lookup that resolves late (e.g. the native
    /// lookup spawned at install time) can't overwrite a newer one (the cua lookup after the swap).
    private var foregroundRefreshGeneration = 0

    init(
        backend: any ComputerUseBackend = ComputerUseBackendFactory.platformDefault().backend(),
        systemSettingsOpener: any QuillCodeDesktopComputerUseSettingsOpening = MacSystemSettingsOpener()
    ) {
        self.backend = backend
        self.systemSettingsOpener = systemSettingsOpener
    }

    func install(on model: QuillCodeWorkspaceModel) {
        model.setComputerUseBackend(backend)
        refreshForegroundApplication(on: model)
    }

    /// Opt-in upgrade to the cua-driver backend (background computer use — no focus/cursor steal).
    /// The native backend is already installed by `install(on:)`, so startup is never blocked on the
    /// driver subprocess; this swaps the live backend only when cua is both preferred (env) and
    /// installed. No-op otherwise, keeping native behavior unchanged for everyone else.
    func resolvePreferredBackend(
        on model: QuillCodeWorkspaceModel,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        locator: CuaDriverLocator = CuaDriverLocator()
    ) async {
        guard ComputerUseBackendFactory.cuaDriverPreferred(environment: environment) else { return }
        guard let cua = await locator.makeBackendIfAvailable(environment: environment) else { return }
        backend = cua
        model.setComputerUseBackend(cua) // also sets status
        refreshForegroundApplication(on: model)
    }

    func refreshStatus(on model: QuillCodeWorkspaceModel) {
        model.setComputerUseStatus(backend.status)
        refreshForegroundApplication(on: model)
    }

    @discardableResult
    func openSystemSettings(
        _ destination: MacSystemSettingsOpener.Destination,
        model: QuillCodeWorkspaceModel
    ) -> Bool {
        let didOpen = systemSettingsOpener.open(destination)
        refreshStatus(on: model)
        return didOpen
    }

    private func refreshForegroundApplication(on model: QuillCodeWorkspaceModel) {
        foregroundRefreshGeneration += 1
        let generation = foregroundRefreshGeneration
        guard let provider = backend as? any ComputerUseForegroundApplicationProviding else {
            model.setComputerUseForegroundApplication(nil)
            return
        }
        Task { [weak self] in
            let application = await provider.foregroundApplication()
            await MainActor.run {
                // Drop the result if a newer refresh has since started (e.g. a backend swap), so a
                // slow native lookup can't overwrite the live cua backend's foreground app.
                guard let self, self.foregroundRefreshGeneration == generation else { return }
                model.setComputerUseForegroundApplication(application)
            }
        }
    }
}
