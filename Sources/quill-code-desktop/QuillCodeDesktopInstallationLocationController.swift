import AppKit
import Combine
import Foundation

@MainActor
final class QuillCodeDesktopInstallationLocationController: ObservableObject {
    enum State: Equatable {
        case ready
        case moving
        case failed(message: String)

        var isBusy: Bool {
            self == .moving
        }
    }

    @Published var isPresented = false
    @Published private(set) var state: State = .ready

    private let configuration: QuillCodeDesktopUpdateConfiguration?
    private var inspectorStorage: (any QuillCodeDesktopUpdateInstallationInspecting)?
    private var relocatorStorage: (any QuillCodeDesktopApplicationRelocating)?
    private let defaults: UserDefaults
    private let relocationUpdateIntentStore: QuillCodeDesktopRelocationUpdateIntentStore
    private let applicationsURL: URL
    private let openApplications: @MainActor (URL) -> Void
    private let hasOtherRunningCopy: @MainActor (String) -> Bool
    private let terminateApplication: @MainActor () -> Void
    private var operationTask: Task<Void, Never>?
    private var generation = UUID()
    private var continuesUpdateAfterRelaunch = false

    init(
        configuration: QuillCodeDesktopUpdateConfiguration? = .bundled(),
        inspector: (any QuillCodeDesktopUpdateInstallationInspecting)? = nil,
        relocator: (any QuillCodeDesktopApplicationRelocating)? = nil,
        defaults: UserDefaults = .standard,
        relocationUpdateIntentStore: QuillCodeDesktopRelocationUpdateIntentStore? = nil,
        applicationsURL: URL = URL(fileURLWithPath: "/Applications", isDirectory: true),
        openApplications: @escaping @MainActor (URL) -> Void = {
            _ = NSWorkspace.shared.open($0)
        },
        hasOtherRunningCopy: @escaping @MainActor (String) -> Bool = { bundleIdentifier in
            let currentProcessID = ProcessInfo.processInfo.processIdentifier
            return NSRunningApplication.runningApplications(
                withBundleIdentifier: bundleIdentifier
            ).contains { application in
                application.processIdentifier != currentProcessID && !application.isTerminated
            }
        },
        terminateApplication: @escaping @MainActor () -> Void =
            QuillCodeDesktopSystemApplication.terminateForUpdate
    ) {
        self.configuration = configuration
        self.inspectorStorage = inspector
        self.relocatorStorage = relocator
        self.defaults = defaults
        self.relocationUpdateIntentStore = relocationUpdateIntentStore
            ?? QuillCodeDesktopRelocationUpdateIntentStore(defaults: defaults)
        self.applicationsURL = applicationsURL.standardizedFileURL
        self.openApplications = openApplications
        self.hasOtherRunningCopy = hasOtherRunningCopy
        self.terminateApplication = terminateApplication
    }

    deinit {
        operationTask?.cancel()
    }

    func startIfNeeded() {
        guard !isPresented, let configuration else { return }
        let pendingUpdate = relocationUpdateIntentStore.hasPendingIntent(
            configuration: configuration
        )
        guard
              inspector.availability(for: configuration) == .requiresRelocation,
              !Self.isInsideApplications(
                  configuration.applicationURL,
                  applicationsURL: applicationsURL
              ),
              pendingUpdate || !defaults.bool(forKey: dismissalKey(for: configuration))
        else {
            return
        }
        continuesUpdateAfterRelaunch = pendingUpdate
        state = .ready
        isPresented = true
    }

    @discardableResult
    func presentForUpdate() -> Bool {
        guard let configuration,
              inspector.availability(for: configuration) == .requiresRelocation,
              !Self.isInsideApplications(
                  configuration.applicationURL,
                  applicationsURL: applicationsURL
              )
        else {
            return false
        }
        continuesUpdateAfterRelaunch = true
        state = .ready
        isPresented = true
        return true
    }

    func dismiss() {
        guard !state.isBusy else { return }
        continuesUpdateAfterRelaunch = false
        guard let configuration else {
            isPresented = false
            return
        }
        defaults.set(true, forKey: dismissalKey(for: configuration))
        isPresented = false
    }

    func openApplicationsFolder() {
        guard !state.isBusy else { return }
        dismiss()
        openApplications(applicationsURL)
    }

    func moveAndRelaunch() {
        guard !state.isBusy else { return }
        isPresented = true
        guard let configuration else {
            state = .failed(
                message: QuillCodeDesktopApplicationRelocationError.invalidSource.localizedDescription
            )
            return
        }
        guard !hasOtherRunningCopy(configuration.bundleIdentifier) else {
            state = .failed(
                message: QuillCodeDesktopApplicationRelocationError.otherCopyRunning.localizedDescription
            )
            return
        }

        operationTask?.cancel()
        generation = UUID()
        let operationGeneration = generation
        state = .moving
        let relocator = relocator
        let applicationsURL = applicationsURL
        let continuesUpdateAfterRelaunch = continuesUpdateAfterRelaunch
        let relocationUpdateIntentStore = relocationUpdateIntentStore
        operationTask = Task { [weak self] in
            do {
                try await relocator.stageAndLaunch(
                    configuration: configuration,
                    applicationsURL: applicationsURL
                )
                try Task.checkCancellation()
                guard let self, self.generation == operationGeneration else { return }
                self.operationTask = nil
                if continuesUpdateAfterRelaunch {
                    relocationUpdateIntentStore.record(configuration: configuration)
                }
                self.terminateApplication()
            } catch is CancellationError {
                guard let self, self.generation == operationGeneration else { return }
                self.operationTask = nil
                self.state = .ready
            } catch {
                guard let self, self.generation == operationGeneration else { return }
                self.operationTask = nil
                self.state = .failed(message: error.localizedDescription)
            }
        }
    }

    var materializedDependencies: Set<Dependency> {
        var dependencies: Set<Dependency> = []
        if inspectorStorage != nil { dependencies.insert(.inspector) }
        if relocatorStorage != nil { dependencies.insert(.relocator) }
        return dependencies
    }

    enum Dependency: Hashable {
        case inspector
        case relocator
    }

    private var inspector: any QuillCodeDesktopUpdateInstallationInspecting {
        if let inspectorStorage { return inspectorStorage }
        let inspector = QuillCodeDesktopUpdateInstallationInspector()
        inspectorStorage = inspector
        return inspector
    }

    private var relocator: any QuillCodeDesktopApplicationRelocating {
        if let relocatorStorage { return relocatorStorage }
        let relocator = QuillCodeDesktopApplicationRelocator()
        relocatorStorage = relocator
        return relocator
    }

    private func dismissalKey(for configuration: QuillCodeDesktopUpdateConfiguration) -> String {
        "QuillCodeInstallLocation.dismissed.\(configuration.bundleIdentifier).\(configuration.currentBuild)"
    }

    private static func isInsideApplications(
        _ applicationURL: URL,
        applicationsURL: URL
    ) -> Bool {
        let applicationPath = applicationURL.standardizedFileURL.path
        let applicationsPath = applicationsURL.standardizedFileURL.path
        return applicationPath.hasPrefix(applicationsPath + "/")
    }
}
