@MainActor
extension QuillCodeDesktopController {
    func scheduleComputerUseStatusRefresh() {
        let coordinator = computerUseCoordinator
        let workspaceModel = model
        tasks.replace(.computerUseStatusRefresh) { [weak self] in
            let changed = await coordinator.refreshStatus(on: workspaceModel)
            guard !Task.isCancelled, changed else { return }
            self?.refresh()
        }
    }

    func scheduleComputerUseForegroundApplicationRefresh() {
        let coordinator = computerUseCoordinator
        let workspaceModel = model
        tasks.replace(.computerUseForegroundRefresh) { [weak self] in
            let changed = await coordinator.refreshForegroundApplication(on: workspaceModel)
            guard !Task.isCancelled, changed else { return }
            self?.refresh()
        }
    }
}
