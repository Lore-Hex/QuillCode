import AppKit
import Foundation

enum QuillCodeDesktopUpdateDependency: Hashable {
    case checker
    case preparer
    case installer
    case installationInspector
    case recovery
}

@MainActor
private final class QuillCodeDesktopUpdateDependencies {
    private var checkerStorage: (any QuillCodeDesktopUpdateChecking)?
    private var preparerStorage: (any QuillCodeDesktopUpdatePreparing)?
    private var installerStorage: (any QuillCodeDesktopUpdateInstalling)?
    private var installationInspectorStorage: (any QuillCodeDesktopUpdateInstallationInspecting)?
    private var recoveryStorage: (any QuillCodeDesktopUpdateRecovering)?

    init(
        checker: (any QuillCodeDesktopUpdateChecking)?,
        preparer: (any QuillCodeDesktopUpdatePreparing)?,
        installer: (any QuillCodeDesktopUpdateInstalling)?,
        installationInspector: (any QuillCodeDesktopUpdateInstallationInspecting)?,
        recovery: (any QuillCodeDesktopUpdateRecovering)?
    ) {
        checkerStorage = checker
        preparerStorage = preparer
        installerStorage = installer
        installationInspectorStorage = installationInspector
        recoveryStorage = recovery
    }

    var checker: any QuillCodeDesktopUpdateChecking {
        if let checkerStorage { return checkerStorage }
        let checker = QuillCodeDesktopUpdateChecker()
        checkerStorage = checker
        return checker
    }

    var preparer: any QuillCodeDesktopUpdatePreparing {
        if let preparerStorage { return preparerStorage }
        let preparer = QuillCodeDesktopUpdatePreparer()
        preparerStorage = preparer
        return preparer
    }

    var installer: any QuillCodeDesktopUpdateInstalling {
        if let installerStorage { return installerStorage }
        let installer = QuillCodeDesktopUpdateInstaller()
        installerStorage = installer
        return installer
    }

    var installationInspector: any QuillCodeDesktopUpdateInstallationInspecting {
        if let installationInspectorStorage { return installationInspectorStorage }
        let inspector = QuillCodeDesktopUpdateInstallationInspector()
        installationInspectorStorage = inspector
        return inspector
    }

    var recovery: any QuillCodeDesktopUpdateRecovering {
        if let recoveryStorage { return recoveryStorage }
        let recovery = QuillCodeDesktopUpdateRecovery()
        recoveryStorage = recovery
        return recovery
    }

    var materialized: Set<QuillCodeDesktopUpdateDependency> {
        var dependencies: Set<QuillCodeDesktopUpdateDependency> = []
        if checkerStorage != nil { dependencies.insert(.checker) }
        if preparerStorage != nil { dependencies.insert(.preparer) }
        if installerStorage != nil { dependencies.insert(.installer) }
        if installationInspectorStorage != nil { dependencies.insert(.installationInspector) }
        if recoveryStorage != nil { dependencies.insert(.recovery) }
        return dependencies
    }
}

@MainActor
final class QuillCodeDesktopUpdateController: ObservableObject {
    @Published private(set) var state: State = .idle
    @Published private(set) var preparationProgress: QuillCodeDesktopUpdatePreparationProgress?
    @Published var isPresented = false

    let configuration: QuillCodeDesktopUpdateConfiguration?
    private let dependencies: QuillCodeDesktopUpdateDependencies
    private let defaults: UserDefaults
    private let now: () -> Date
    private let automaticSchedule: QuillCodeDesktopUpdateSchedule
    private let reminderStore: QuillCodeDesktopUpdateReminderStore
    private let relocationUpdateIntentStore: QuillCodeDesktopRelocationUpdateIntentStore
    private let relocationContinuationTimeout: Duration
    private let installResultURL: URL?
    private let terminateApplication: @MainActor () -> Void
    private var operationTask: Task<Void, Never>?
    private var automaticTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var generation = UUID()
    private var didStartAutomaticChecks = false
    private lazy var relocationContinuation = QuillCodeDesktopRelocationUpdateContinuation(
        intentStore: relocationUpdateIntentStore,
        installationInspector: dependencies.installationInspector,
        resultURL: installResultURL,
        timeout: relocationContinuationTimeout
    )

    private enum AutomaticCheckOutcome {
        case success(nextCheckDelay: TimeInterval?)
        case failure
        case deferred
        case rescheduled(TimeInterval)
    }

    init(
        configuration: QuillCodeDesktopUpdateConfiguration? = .bundled(),
        checker: (any QuillCodeDesktopUpdateChecking)? = nil,
        preparer: (any QuillCodeDesktopUpdatePreparing)? = nil,
        installer: (any QuillCodeDesktopUpdateInstalling)? = nil,
        installationInspector: (any QuillCodeDesktopUpdateInstallationInspecting)? = nil,
        recovery: (any QuillCodeDesktopUpdateRecovering)? = nil,
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
        self.dependencies = QuillCodeDesktopUpdateDependencies(
            checker: checker,
            preparer: preparer,
            installer: installer,
            installationInspector: installationInspector,
            recovery: recovery
        )
        self.defaults = defaults
        self.now = now
        self.automaticSchedule = automaticSchedule
        self.reminderStore = QuillCodeDesktopUpdateReminderStore(
            defaults: defaults,
            reminderInterval: reminderInterval
        )
        self.relocationUpdateIntentStore = relocationUpdateIntentStore
            ?? QuillCodeDesktopRelocationUpdateIntentStore(defaults: defaults, now: now)
        self.relocationContinuationTimeout = relocationContinuationTimeout
        self.installResultURL = installResultURL
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
            _ = QuillCodeDesktopUpdateInstallResultReader.take(from: installResultURL)
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

    var materializedUpdateDependencies: Set<QuillCodeDesktopUpdateDependency> {
        dependencies.materialized
    }

    private var checker: any QuillCodeDesktopUpdateChecking {
        dependencies.checker
    }

    private var preparer: any QuillCodeDesktopUpdatePreparing {
        dependencies.preparer
    }

    private var installer: any QuillCodeDesktopUpdateInstalling {
        dependencies.installer
    }

    private var installationInspector: any QuillCodeDesktopUpdateInstallationInspecting {
        dependencies.installationInspector
    }

    private var recovery: any QuillCodeDesktopUpdateRecovering {
        dependencies.recovery
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
