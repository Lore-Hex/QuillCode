import Foundation
import QuillCodeApp

@MainActor
final class QuillCodeDesktopRelocationUpdateContinuation {
    enum Action: Equatable {
        case none
        case awaitingResult
        case checkForUpdates
        case failed(message: String)
    }

    struct Startup: Equatable {
        var action: Action
        var delaysAutomaticCheck: Bool
    }

    private static let mismatchedResultMessage =
        "\(QuillCodeProduct.displayName) could not confirm the completed move. Reopen it and check for updates again."

    private let intentStore: QuillCodeDesktopRelocationUpdateIntentStore
    private let installationInspector: any QuillCodeDesktopUpdateInstallationInspecting
    private let resultURL: URL?
    private let timeout: Duration
    private var resultTask: Task<Void, Never>?

    init(
        intentStore: QuillCodeDesktopRelocationUpdateIntentStore,
        installationInspector: any QuillCodeDesktopUpdateInstallationInspecting,
        resultURL: URL?,
        timeout: Duration
    ) {
        self.intentStore = intentStore
        self.installationInspector = installationInspector
        self.resultURL = resultURL
        self.timeout = timeout
    }

    deinit {
        resultTask?.cancel()
    }

    func start(
        configuration: QuillCodeDesktopUpdateConfiguration,
        onCompletion: @escaping @MainActor (Action) -> Void
    ) -> Startup {
        let previousResult = QuillCodeDesktopUpdateInstallResultReader.take(from: resultURL)
        let hasIntent = intentStore.hasPendingIntent(configuration: configuration)

        if let previousResult, previousResult.status == .failure {
            if hasIntent {
                _ = intentStore.consume(configuration: configuration)
            }
            return Startup(
                action: .failed(message: previousResult.message),
                delaysAutomaticCheck: hasIntent
            )
        }
        guard hasIntent else {
            return Startup(action: .none, delaysAutomaticCheck: false)
        }
        if let previousResult {
            _ = intentStore.consume(configuration: configuration)
            guard resultMatches(previousResult, configuration: configuration) else {
                return Startup(
                    action: .failed(message: Self.mismatchedResultMessage),
                    delaysAutomaticCheck: true
                )
            }
            return Startup(action: .checkForUpdates, delaysAutomaticCheck: true)
        }

        waitForResult(configuration: configuration, onCompletion: onCompletion)
        return Startup(action: .awaitingResult, delaysAutomaticCheck: true)
    }

    private func waitForResult(
        configuration: QuillCodeDesktopUpdateConfiguration,
        onCompletion: @escaping @MainActor (Action) -> Void
    ) {
        resultTask?.cancel()
        let resultURL = resultURL
        let timeout = timeout
        resultTask = Task { [weak self] in
            let result = await QuillCodeDesktopUpdateInstallResultReader.wait(
                at: resultURL,
                timeout: timeout
            )
            guard !Task.isCancelled, let self else { return }
            self.resultTask = nil
            if let result {
                _ = self.intentStore.consume(configuration: configuration)
                if result.status == .failure {
                    onCompletion(.failed(message: result.message))
                } else if self.resultMatches(result, configuration: configuration) {
                    onCompletion(.checkForUpdates)
                } else {
                    onCompletion(.failed(message: Self.mismatchedResultMessage))
                }
                return
            }
            guard self.installationInspector.availability(for: configuration) == .available,
                  self.intentStore.consume(configuration: configuration)
            else {
                return
            }
            onCompletion(.checkForUpdates)
        }
    }

    private func resultMatches(
        _ result: QuillCodeDesktopUpdateInstallResult,
        configuration: QuillCodeDesktopUpdateConfiguration
    ) -> Bool {
        result.status == .success &&
            result.version == configuration.currentVersion &&
            result.build == configuration.currentBuild
    }
}
