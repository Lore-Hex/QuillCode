import AppKit
import Foundation
import QuillCodePersistence

@MainActor
final class QuillCodeDesktopUpdateController: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case updateAvailable(QuillCodeDesktopUpdateRelease)
        case downloading(QuillCodeDesktopUpdateRelease)
        case installing(QuillCodeDesktopUpdateRelease)
        case upToDate(latestVersion: String, latestBuild: String)
        case failed(message: String, release: QuillCodeDesktopUpdateRelease?)

        var release: QuillCodeDesktopUpdateRelease? {
            switch self {
            case .updateAvailable(let release), .downloading(let release), .installing(let release):
                return release
            case .failed(_, let release):
                return release
            case .idle, .checking, .upToDate:
                return nil
            }
        }

        var isBusy: Bool {
            switch self {
            case .checking, .downloading, .installing:
                return true
            case .idle, .updateAvailable, .upToDate, .failed:
                return false
            }
        }
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var preparationProgress: QuillCodeDesktopUpdatePreparationProgress?
    @Published var isPresented = false

    let configuration: QuillCodeDesktopUpdateConfiguration?
    private let checker: any QuillCodeDesktopUpdateChecking
    private let preparer: any QuillCodeDesktopUpdatePreparing
    private let installer: any QuillCodeDesktopUpdateInstalling
    private let recovery: any QuillCodeDesktopUpdateRecovering
    private let defaults: UserDefaults
    private let now: () -> Date
    private let automaticSchedule: QuillCodeDesktopUpdateSchedule
    private let installResultURL: URL?
    private let terminateApplication: @MainActor () -> Void
    private var operationTask: Task<Void, Never>?
    private var automaticTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var generation = UUID()
    private var didStartAutomaticChecks = false

    private enum AutomaticCheckOutcome {
        case success
        case failure
        case deferred
        case rescheduled(TimeInterval)
    }

    init(
        configuration: QuillCodeDesktopUpdateConfiguration? = .bundled(),
        checker: any QuillCodeDesktopUpdateChecking = QuillCodeDesktopUpdateChecker(),
        preparer: any QuillCodeDesktopUpdatePreparing = QuillCodeDesktopUpdatePreparer(),
        installer: any QuillCodeDesktopUpdateInstalling = QuillCodeDesktopUpdateInstaller(),
        recovery: any QuillCodeDesktopUpdateRecovering = QuillCodeDesktopUpdateRecovery(),
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        automaticSchedule: QuillCodeDesktopUpdateSchedule = .production,
        installResultURL: URL? = try? QuillCodeDesktopUpdatePaths.installResultURL(),
        terminateApplication: @escaping @MainActor () -> Void =
            QuillCodeDesktopSystemApplication.terminateForUpdate
    ) {
        self.configuration = configuration
        self.checker = checker
        self.preparer = preparer
        self.installer = installer
        self.recovery = recovery
        self.defaults = defaults
        self.now = now
        self.automaticSchedule = automaticSchedule
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
        consumePreviousInstallResult()
        guard let configuration else { return }

        let recovery = recovery
        recoveryTask = Task {
            await recovery.recoverInterruptedUpdate(configuration: configuration)
        }

        let schedule = automaticSchedule
        let firstDelay = schedule.firstDelay(
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
                case .success:
                    delay = schedule.interval(for: configuration.channel)
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
        let generation = beginNewOperation()
        state = .downloading(release)
        preparationProgress = .downloading(receivedBytes: 0, totalBytes: release.asset.sizeBytes)
        operationTask = Task { [weak self] in
            guard let self else { return }
            defer { self.finishOperation(generation: generation) }
            do {
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
        isPresented = false
    }

    func openReleasePage() {
        guard let release = state.release else { return }
        NSWorkspace.shared.open(release.releaseURL)
    }

    func openDownloadInBrowser() {
        guard let release = state.release else { return }
        NSWorkspace.shared.open(release.asset.url)
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
            applySuccessfulCheck(result, userInitiated: true, configuration: configuration)
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
        guard remaining == 0 else { return .rescheduled(remaining) }
        guard !state.isBusy, !isPresented else { return .deferred }
        let startingGeneration = generation
        do {
            let result = try await checker.check(configuration: configuration)
            try Task.checkCancellation()
            guard generation == startingGeneration, !state.isBusy, !isPresented else {
                return .deferred
            }
            applySuccessfulCheck(result, userInitiated: false, configuration: configuration)
            return .success
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
    ) {
        defaults.set(now(), forKey: lastCheckKey(configuration: configuration))
        switch result {
        case .updateAvailable(let release):
            state = .updateAvailable(release)
            isPresented = true
        case .upToDate(let latestVersion, let latestBuild):
            state = userInitiated
                ? .upToDate(latestVersion: latestVersion, latestBuild: latestBuild)
                : .idle
        }
    }

    private func beginNewOperation() -> UUID {
        operationTask?.cancel()
        operationTask = nil
        preparationProgress = nil
        generation = UUID()
        return generation
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

    private func consumePreviousInstallResult() {
        guard let installResultURL else { return }
        defer { try? FileManager.default.removeItem(at: installResultURL) }

        guard let data = try? BoundedFileDataReader.readIfPresent(
            from: installResultURL,
            maximumBytes: QuillCodeDesktopUpdateInstallResult.maximumEncodedBytes
        ),
              let result = try? JSONDecoder().decode(QuillCodeDesktopUpdateInstallResult.self, from: data)
        else {
            return
        }
        guard result.status == .failure else { return }
        state = .failed(message: result.message, release: nil)
        isPresented = true
    }
}
