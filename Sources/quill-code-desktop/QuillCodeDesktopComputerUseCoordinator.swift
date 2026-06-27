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
        backend: any ComputerUseBackend = MacComputerUseBackend(),
        systemSettingsOpener: any QuillCodeDesktopComputerUseSettingsOpening = MacSystemSettingsOpener()
    ) {
        self.backend = backend
        self.systemSettingsOpener = systemSettingsOpener
    }

    func install(on model: QuillCodeWorkspaceModel) {
        model.setComputerUseBackend(backend)
    }

    func refreshStatus(on model: QuillCodeWorkspaceModel) {
        model.setComputerUseStatus(backend.status)
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
}
