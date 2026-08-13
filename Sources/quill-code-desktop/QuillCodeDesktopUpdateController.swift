import AppKit
import Foundation

@MainActor
final class QuillCodeDesktopUpdateController: ObservableObject {
    @Published private(set) var state: State = .idle
    @Published private(set) var preparationProgress: QuillCodeDesktopUpdatePreparationProgress?
    @Published var isPresented = false

    let configuration: QuillCodeDesktopUpdateConfiguration?
    private let checker: any QuillCodeDesktopUpdateChecking
    private let preparer: any QuillCodeDesktopUpdatePreparing
    private let installer: any QuillCodeDesktopUpdateInstalling
    private let installationInspector: any QuillCodeDesktopUpdateInstallationInspecting
    private let recovery: any QuillCodeDesktopUpdateRecovering
    private let defaults: UserDefaults
    private let now: () -> Date
    private let automaticSchedule: QuillCodeDesktopUpdateSchedule
    private let reminderStore: QuillCodeDesktopUpdateReminderStore
    private let relocationContinuation: QuillCodeDesktopRelocationUpdateContinuation
    private let terminateApplication: @MainActor () -> Void
    private var operationTask: Task<Void, Never>?
    private var automaticTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var generation = UUID()
    private var didStartAutomaticChecks = false

    private enum AutomaticCheckOutcome {
        case success(nextCheckDelay: TimeInterval?)
        case failure
        case deferred
        case rescheduled(TimeInterval)
    }

    init(
        configuration: QuillCodeDesktopUpdateConfiguration? = .bundled(),
        checker: any QuillCodeDesktopUpdateChecking = QuillCodeDesktopUpdateChecker(),
        preparer: any QuillCodeDesktopUpdatePreparing = QuillCodeDesktopUpdatePreparer(),
        installer: any QuillCodeDesktopUpdateInstalling = QuillCodeDesktopUpdateInstaller(),
        installationInspector: any QuillCodeDesktopUpdateInstallationInspecting =
            QuillCodeDesktopUpdateInstallationInspector(),
        recovery: any QuillCodeDesktopUpdateRecovering = QuillCodeDesktopUpdateRecovery(),
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        automaticSchedule: QuillCodeDesktopUpdateSchedule = .production,
        reminderInterval: TimeInterval = QuillCodeDesktopUpdateReminderStore.productionInterval,
        relocationUpdateIntentStore: QuillCodeDesktopRelocationUpdateIntentStore? = nil,
        relocationContinuationTimeout: Duration = .seconds(15),
        installResultURL: URL? = try? QuillCodeDesktopUpdatePaths.installResultURL(),
        terminateApplication: @escaping @MainActor () -> Void =
            QuillCodeDesktopSystemApplication.terminateForUpdate
    ) {
        self.configuration = configuration
        self.checker = checker
        self.preparer = preparer
        self.installer = installer
        self.installationInspector = installationInspector
        self.recovery = recovery
        self.defaults = defaults
        self.now = now
        self.automaticSchedule = automaticSchedule
        self.reminderStore = QuillCodeDesktopUpdateReminderStore(
            defaults: defaults,
            reminderInterval: reminderInterval
        )
        let intentStore = relocationUpdateIntentStore
            ?? QuillCodeDesktopRelocationUpdateIntentStore(defaults: defaults, now: now)
        self.relocationContinuation = QuillCodeDesktopRelocationUpdateContinuation(
            intentStore: intentStore,
            installationInspector: installationInspector,
            resultURL: installResultURL,
            timeout: relocationContinuationTimeout
        )
        self.terminateApplication = terminateApplication
    }

    deinit {
        operationTask?.cancel()
        automaticTask?.cancel()
        recoveryTask?.cancel()
    }

    func startAutomaticChecks() {
        guard !didStartAutomaticChecks else { return }
        didStartAutomaticChecks = true
        guard let configuration else {
            relocationContinuation.discardPreviousResult()
            return
        }
        let continuationStartup = relocationContinuation.start(
            configuration: configuration,
            onCompletion: { [weak self] action in
                self?.applyRelocationContinuationAction(action)
            }
        )

        let recovery = recovery
        recoveryTask = Task {
            await recovery.recoverInterruptedUpdate(configuration: configuration)
        }

        applyRelocationContinuationAction(continuationStartup.action)

        let schedule = automaticSchedule
        let firstDelay = continuationStartup.delaysAutomaticCheck
            ? schedule.interval(for: configuration.channel)
            : schedule.firstDelay(
                lastSuccessfulCheck: lastSuccessfulCheck(configuration: configuration),
                now: now(),
                channel: configuration.channel
            )
        automaticTask = Task { [weak self] in
            var delay = firstDelay
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    return
                }
                guard let outcome = await self?.performAutomaticCheck(configuration: configuration) else {
                    return
                }
                switch outcome {
                case .success(let nextCheckDelay):
                    delay = nextCheckDelay ?? schedule.interval(for: configuration.channel)
                case .failure:
                    delay = schedule.failureRetryInterval
                case .deferred:
                    delay = schedule.busyRetryInterval
                case .rescheduled(let remaining):
                    delay = remaining
                }
            }
        }
    }

    func checkForUpdates() {
        isPresented = true
        guard !state.isBusy else { return }
        if let configuration {
            reminderStore.clear(configuration: configuration)
        }
        let generation = beginNewOperation()
        state = .checking
        operationTask = Task { [weak self] in
            guard let self else { return }
            await self.performUserCheck(generation: generation)
        }
    }

    func updateAndRelaunch() {
        guard !state.isBusy else {
            isPresented = true
            return
        }
        guard let configuration,
              let release = state.release
        else {
            state = .failed(
                message: QuillCodeDesktopUpdateError.updatesUnavailable.localizedDescription,
                release: nil
            )
            return
        }
        reminderStore.clear(configuration: configuration)
        guard installationInspector.availability(for: configuration) == .available else {
            state = .failed(
                message: QuillCodeDesktopUpdateError.installationUnavailable.localizedDescription,
                release: release
            )
            isPresented = true
            return
        }
        let recoveryTask = cancelRecoveryAndTakeTask()
        let generation = beginNewOperation()
        state = .downloading(release)
        preparationProgress = .downloading(receivedBytes: 0, totalBytes: release.asset.sizeBytes)
        operationTask = Task { [weak self] in
            guard let self else { return }
            defer { self.finishOperation(generation: generation) }
            do {
                if let recoveryTask {
                    await recoveryTask.value
                }
                try Task.checkCancellation()
                guard self.generation == generation else { return }
                let prepared = try await self.prepareUpdate(
                    release: release,
                    configuration: configuration,
                    generation: generation
                )
                try Task.checkCancellation()
                guard self.generation == generation else { return }
                self.preparationProgress = nil
                self.state = .installing(release)
                try await installer.stageAndLaunch(
                    preparedUpdate: prepared,
                    configuration: configuration
                )
                try Task.checkCancellation()
                guard self.generation == generation else { return }
                self.terminateApplication()
            } catch is CancellationError {
                guard self.generation == generation else { return }
                self.preparationProgress = nil
                self.state = .updateAvailable(release)
            } catch {
                guard self.generation == generation else { return }
                self.preparationProgress = nil
                self.state = .failed(message: error.localizedDescription, release: release)
            }
        }
    }

    func cancelCurrentOperation() {
        guard case .downloading(let release) = state else { return }
        _ = beginNewOperation()
        state = .updateAvailable(release)
    }

    func dismiss() {
        guard !state.isBusy else { return }
        if case .updateAvailable(let release) = state,
           let configuration {
            reminderStore.recordDeferral(release, configuration: configuration, now: now())
        }
        isPresented = false
    }

    func openReleasePage() {
        guard let release = state.release else { return }
        NSWorkspace.shared.open(release.releaseURL)
    }

    func openManualInstaller() {
        guard let release = state.release else { return }
        NSWorkspace.shared.open(release.manualInstallationURL)
    }

    var updateRequiresRelocation: Bool {
        guard state.release != nil,
              let configuration
        else {
            return false
        }
        return installationInspector.availability(for: configuration) == .requiresRelocation
    }

    private func performUserCheck(generation: UUID) async {
        defer { finishOperation(generation: generation) }
        guard let configuration else {
            guard self.generation == generation else { return }
            state = .failed(
                message: QuillCodeDesktopUpdateError.updatesUnavailable.localizedDescription,
                release: nil
            )
            return
        }
        do {
            let result = try await checker.check(configuration: configuration)
            try Task.checkCancellation()
            guard self.generation == generation else { return }
            _ = applySuccessfulCheck(result, userInitiated: true, configuration: configuration)
        } catch is CancellationError {
            return
        } catch {
            guard self.generation == generation else { return }
            state = .failed(message: error.localizedDescription, release: nil)
        }
    }

    private func performAutomaticCheck(
        configuration: QuillCodeDesktopUpdateConfiguration
    ) async -> AutomaticCheckOutcome {
        let remaining = automaticSchedule.remainingDelay(
            lastSuccessfulCheck: lastSuccessfulCheck(configuration: configuration),
            now: now(),
            channel: configuration.channel
        )
        if remaining > 0,
           case .updateAvailable(let release) = state,
           !isPresented {
            if let reminderRemaining = reminderStore.remainingDeferral(
                for: release,
                configuration: configuration,
                now: now()
            ) {
                return .rescheduled(min(remaining, reminderRemaining))
            }
            isPresented = true
        }
        guard remaining == 0 else { return .rescheduled(remaining) }
        guard !state.isBusy, !isPresented else { return .deferred }
        let startingGeneration = generation
        do {
            let result = try await checker.check(configuration: configuration)
            try Task.checkCancellation()
            guard generation == startingGeneration, !state.isBusy, !isPresented else {
                return .deferred
            }
            let nextCheckDelay = applySuccessfulCheck(
                result,
                userInitiated: false,
                configuration: configuration
            )
            return .success(nextCheckDelay: nextCheckDelay)
        } catch is CancellationError {
            return .deferred
        } catch {
            return .failure
        }
    }

    private func applySuccessfulCheck(
        _ result: QuillCodeDesktopUpdateCheckResult,
        userInitiated: Bool,
        configuration: QuillCodeDesktopUpdateConfiguration
    ) -> TimeInterval? {
        defaults.set(now(), forKey: lastCheckKey(configuration: configuration))
        switch result {
        case .updateAvailable(let release):
            state = .updateAvailable(release)
            guard !userInitiated else {
                isPresented = true
                return nil
            }
            let remainingDeferral = reminderStore.remainingDeferral(
                for: release,
                configuration: configuration,
                now: now()
            )
            isPresented = remainingDeferral == nil
            return remainingDeferral.map {
                min($0, automaticSchedule.interval(for: configuration.channel))
            }
        case .upToDate(let latestVersion, let latestBuild):
            reminderStore.clear(configuration: configuration)
            state = userInitiated
                ? .upToDate(latestVersion: latestVersion, latestBuild: latestBuild)
                : .idle
            return nil
        }
    }

    private func beginNewOperation() -> UUID {
        operationTask?.cancel()
        operationTask = nil
        preparationProgress = nil
        generation = UUID()
        return generation
    }

    private func cancelRecoveryAndTakeTask() -> Task<Void, Never>? {
        let task = recoveryTask
        recoveryTask = nil
        task?.cancel()
        return task
    }

    private func prepareUpdate(
        release: QuillCodeDesktopUpdateRelease,
        configuration: QuillCodeDesktopUpdateConfiguration,
        generation: UUID
    ) async throws -> QuillCodeDesktopPreparedUpdate {
        let (progressStream, progressContinuation) = AsyncStream.makeStream(
            of: QuillCodeDesktopUpdatePreparationProgress.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        let progressTask = Task { @MainActor [weak self] in
            for await progress in progressStream {
                guard let self,
                      self.generation == generation,
                      case .downloading = self.state
                else {
                    return
                }
                self.preparationProgress = progress
            }
        }
        defer {
            progressContinuation.finish()
            progressTask.cancel()
        }
        return try await preparer.prepare(
            release: release,
            configuration: configuration,
            progress: { progressContinuation.yield($0) }
        )
    }

    private func finishOperation(generation: UUID) {
        guard self.generation == generation else { return }
        operationTask = nil
    }

    private func lastSuccessfulCheck(
        configuration: QuillCodeDesktopUpdateConfiguration
    ) -> Date? {
        defaults.object(
            forKey: lastCheckKey(configuration: configuration)
        ) as? Date
    }

    private func lastCheckKey(configuration: QuillCodeDesktopUpdateConfiguration) -> String {
        "QuillCodeUpdater.lastSuccessfulCheck.\(configuration.channel.rawValue)"
    }

    private func applyRelocationContinuationAction(
        _ action: QuillCodeDesktopRelocationUpdateContinuation.Action
    ) {
        switch action {
        case .none, .awaitingResult:
            return
        case .checkForUpdates:
            checkForUpdates()
        case .failed(let message):
            _ = beginNewOperation()
            state = .failed(message: message, release: nil)
            isPresented = true
        }
    }
}
