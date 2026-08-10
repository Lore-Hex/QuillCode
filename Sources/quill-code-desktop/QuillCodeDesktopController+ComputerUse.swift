@MainActor
extension QuillCodeDesktopController {
    func scheduleComputerUseStatusRefresh() {
        if computerUseCoordinator.refreshStatus(on: model) {
            refresh()
        }

        let coordinator = computerUseCoordinator
        let workspaceModel = model
        tasks.replace(.computerUseForegroundRefresh) { [weak self] in
            let changed = await coordinator.refreshForegroundApplication(on: workspaceModel)
            guard !Task.isCancelled, changed else { return }
            self?.refresh()
        }
    }
}
