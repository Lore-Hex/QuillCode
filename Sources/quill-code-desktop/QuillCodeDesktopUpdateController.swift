import AppKit
import Foundation

@MainActor
final class QuillCodeDesktopUpdateController: ObservableObject {
    private static let installResultByteLimit = 64 * 1_024

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
    @Published var isPresented = false

    let configuration: QuillCodeDesktopUpdateConfiguration?
    private let checker: any QuillCodeDesktopUpdateChecking
    private let preparer: any QuillCodeDesktopUpdatePreparing
    private let installer: any QuillCodeDesktopUpdateInstalling
    private let defaults: UserDefaults
    private let now: () -> Date
    private let automaticCheckDelay: Duration
    private let installResultURL: URL?
    private let terminateApplication: @MainActor () -> Void
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var didStartAutomaticChecks = false

    init(
        configuration: QuillCodeDesktopUpdateConfiguration? = .bundled(),
        checker: any QuillCodeDesktopUpdateChecking = QuillCodeDesktopUpdateChecker(),
        preparer: any QuillCodeDesktopUpdatePreparing = QuillCodeDesktopUpdatePreparer(),
        installer: any QuillCodeDesktopUpdateInstalling = QuillCodeDesktopUpdateInstaller(),
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        automaticCheckDelay: Duration = .seconds(3),
        installResultURL: URL? = try? QuillCodeDesktopUpdatePaths.installResultURL(),
        terminateApplication: @escaping @MainActor () -> Void =
            QuillCodeDesktopSystemApplication.terminateForUpdate
    ) {
        self.configuration = configuration
        self.checker = checker
        self.preparer = preparer
        self.installer = installer
        self.defaults = defaults
        self.now = now
        self.automaticCheckDelay = automaticCheckDelay
        self.installResultURL = installResultURL
        self.terminateApplication = terminateApplication
    }

    deinit {
        task?.cancel()
    }

    func startAutomaticChecks() {
        guard !didStartAutomaticChecks else { return }
        didStartAutomaticChecks = true
        consumePreviousInstallResult()
        guard let configuration, shouldAutomaticallyCheck(configuration: configuration) else { return }

        let generation = beginNewTask()
        task = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.automaticCheckDelay)
            guard !Task.isCancelled else { return }
            await self.performCheck(userInitiated: false, generation: generation)
        }
    }

    func checkForUpdates() {
        isPresented = true
        let generation = beginNewTask()
        state = .checking
        task = Task { [weak self] in
            guard let self else { return }
            await self.performCheck(userInitiated: true, generation: generation)
        }
    }

    func updateAndRelaunch() {
        guard let configuration,
              let release = state.release
        else {
            state = .failed(
                message: QuillCodeDesktopUpdateError.updatesUnavailable.localizedDescription,
                release: nil
            )
            return
        }
        let generation = beginNewTask()
        state = .downloading(release)
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let prepared = try await preparer.prepare(
                    release: release,
                    configuration: configuration
                )
                try Task.checkCancellation()
                guard self.generation == generation else { return }
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
                self.state = .updateAvailable(release)
            } catch {
                guard self.generation == generation else { return }
                self.state = .failed(message: error.localizedDescription, release: release)
            }
        }
    }

    func cancelCurrentOperation() {
        guard let release = state.release else { return }
        _ = beginNewTask()
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

    private func performCheck(userInitiated: Bool, generation: UUID) async {
        guard let configuration else {
            guard userInitiated, self.generation == generation else { return }
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
        } catch is CancellationError {
            return
        } catch {
            guard self.generation == generation else { return }
            state = userInitiated
                ? .failed(message: error.localizedDescription, release: nil)
                : .idle
        }
    }

    private func beginNewTask() -> UUID {
        task?.cancel()
        generation = UUID()
        return generation
    }

    private func shouldAutomaticallyCheck(
        configuration: QuillCodeDesktopUpdateConfiguration
    ) -> Bool {
        guard let lastCheck = defaults.object(
            forKey: lastCheckKey(configuration: configuration)
        ) as? Date else {
            return true
        }
        let interval: TimeInterval = configuration.channel == .tester ? 6 * 60 * 60 : 24 * 60 * 60
        return now().timeIntervalSince(lastCheck) >= interval
    }

    private func lastCheckKey(configuration: QuillCodeDesktopUpdateConfiguration) -> String {
        "QuillCodeUpdater.lastSuccessfulCheck.\(configuration.channel.rawValue)"
    }

    private func consumePreviousInstallResult() {
        guard let installResultURL,
              FileManager.default.fileExists(atPath: installResultURL.path)
        else {
            return
        }
        defer { try? FileManager.default.removeItem(at: installResultURL) }

        guard let values = try? installResultURL.resourceValues(
            forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        ),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              let fileSize = values.fileSize,
              fileSize <= Self.installResultByteLimit,
              let data = try? Data(contentsOf: installResultURL, options: .mappedIfSafe),
              let result = try? JSONDecoder().decode(QuillCodeDesktopUpdateInstallResult.self, from: data)
        else {
            return
        }
        guard result.status == .failure else { return }
        state = .failed(message: result.message, release: nil)
        isPresented = true
    }
}
