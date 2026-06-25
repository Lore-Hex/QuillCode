import Foundation
import QuillCodeApp

@MainActor
struct QuillCodeDesktopAutomationCoordinator {
    private let tickIntervalNanoseconds: UInt64

    init(tickIntervalNanoseconds: UInt64 = 30_000_000_000) {
        self.tickIntervalNanoseconds = tickIntervalNanoseconds
    }

    func startTicker(
        model: QuillCodeWorkspaceModel,
        tasks: QuillCodeDesktopTaskCoordinator,
        notifier: any QuillCodeAutomationNotifying,
        refresh: @escaping @MainActor () -> Void
    ) {
        tasks.replace(.automationTicker) {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: tickIntervalNanoseconds)
                guard !Task.isCancelled else { return }
                runDueAutomations(model: model, notifier: notifier, refresh: refresh)
            }
        }
    }

    func runDueAutomations(
        model: QuillCodeWorkspaceModel,
        notifier: any QuillCodeAutomationNotifying,
        refresh: @escaping @MainActor () -> Void
    ) {
        let reports = model.runDueAutomationReports()
        guard !reports.isEmpty else { return }

        reports.forEach(notifier.deliver)
        refresh()
    }
}
