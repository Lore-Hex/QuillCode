import Foundation
import QuillCodeApp
import QuillComputerUseKit

protocol QuillCodeDesktopComputerUseSettingsOpening {
    @discardableResult
    func open(_ destination: MacSystemSettingsOpener.Destination) -> Bool
}

extension MacSystemSettingsOpener: QuillCodeDesktopComputerUseSettingsOpening {}

@MainActor
struct QuillCodeDesktopComputerUseCoordinator {
    private let backend: any ComputerUseBackend
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
