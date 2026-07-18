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
        model.setComputerUseBackend(cua)
        model.setComputerUseStatus(cua.status)
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
        guard let provider = backend as? any ComputerUseForegroundApplicationProviding else {
            model.setComputerUseForegroundApplication(nil)
            return
        }
        Task {
            let application = await provider.foregroundApplication()
            await MainActor.run {
                model.setComputerUseForegroundApplication(application)
            }
        }
    }
}
