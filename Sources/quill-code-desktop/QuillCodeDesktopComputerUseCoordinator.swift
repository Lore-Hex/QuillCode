import AppKit
import Foundation
import QuillCodeApp
import QuillComputerUseKit

protocol QuillCodeDesktopComputerUseSettingsOpening {
    @discardableResult
    func open(_ destination: MacSystemSettingsOpener.Destination) -> Bool
}

extension MacSystemSettingsOpener: QuillCodeDesktopComputerUseSettingsOpening {}

@MainActor
final class QuillCodeDesktopComputerUseCoordinator: NSObject {
    private var backend: any ComputerUseBackend
    private let systemSettingsOpener: any QuillCodeDesktopComputerUseSettingsOpening
    private let applicationActivationNotificationCenter: NotificationCenter
    private let applicationActivationNotification: Notification.Name
    private var applicationActivationHandler: (@MainActor () -> Void)?
    /// Monotonic token so an in-flight foreground-app lookup cannot overwrite a newer one after a
    /// backend swap or rapid application activation sequence.
    private var foregroundRefreshGeneration = 0

    init(
        backend: any ComputerUseBackend = ComputerUseBackendFactory.platformDefault().backend(),
        systemSettingsOpener: any QuillCodeDesktopComputerUseSettingsOpening = MacSystemSettingsOpener(),
        applicationActivationNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        applicationActivationNotification: Notification.Name = NSWorkspace.didActivateApplicationNotification
    ) {
        self.backend = backend
        self.systemSettingsOpener = systemSettingsOpener
        self.applicationActivationNotificationCenter = applicationActivationNotificationCenter
        self.applicationActivationNotification = applicationActivationNotification
        super.init()
    }

    deinit {
        applicationActivationNotificationCenter.removeObserver(self)
    }

    func install(on model: QuillCodeWorkspaceModel) {
        model.setComputerUseBackend(backend)
    }

    func startApplicationActivationObservation(
        onActivation: @escaping @MainActor () -> Void
    ) {
        guard applicationActivationHandler == nil else { return }
        applicationActivationHandler = onActivation
        applicationActivationNotificationCenter.addObserver(
            self,
            selector: #selector(applicationDidActivate),
            name: applicationActivationNotification,
            object: nil
        )
    }

    /// Opt-in upgrade to the cua-driver backend (background computer use — no focus/cursor steal).
    /// The native backend is already installed by `install(on:)`, so startup is never blocked on the
    /// driver subprocess; this swaps the live backend only when cua is both preferred (env) and
    /// installed. No-op otherwise, keeping native behavior unchanged for everyone else.
    func resolvePreferredBackend(
        on model: QuillCodeWorkspaceModel,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        locator: CuaDriverLocator = CuaDriverLocator()
    ) async {
        guard ComputerUseBackendFactory.cuaDriverPreferred(environment: environment) else { return }
        guard let cua = await locator.makeBackendIfAvailable(environment: environment) else { return }
        backend = cua
        model.setComputerUseBackend(cua) // also sets status
    }

    @discardableResult
    func refreshForegroundApplication(on model: QuillCodeWorkspaceModel) async -> Bool {
        guard !Task.isCancelled else { return false }
        foregroundRefreshGeneration &+= 1
        let generation = foregroundRefreshGeneration
        guard let provider = backend as? any ComputerUseForegroundApplicationProviding else {
            guard model.root.topBar.computerUseForegroundApplication != nil else { return false }
            model.setComputerUseForegroundApplication(nil)
            return true
        }
        let application = await provider.foregroundApplication()
        guard !Task.isCancelled, foregroundRefreshGeneration == generation else { return false }
        guard model.root.topBar.computerUseForegroundApplication != application else { return false }
        model.setComputerUseForegroundApplication(application)
        return true
    }

    @discardableResult
    func refreshStatus(on model: QuillCodeWorkspaceModel) -> Bool {
        let status = backend.status
        guard model.root.topBar.computerUseStatus != status else { return false }
        model.setComputerUseStatus(status)
        return true
    }

    @discardableResult
    func openSystemSettings(
        _ destination: MacSystemSettingsOpener.Destination
    ) -> Bool {
        if let permissionRequester = backend as? any ComputerUsePermissionRequesting {
            switch destination {
            case .screenRecording:
                permissionRequester.requestScreenRecordingAccess()
            case .accessibility:
                permissionRequester.requestAccessibilityAccess()
            }
        }
        let didOpen = systemSettingsOpener.open(destination)
        return didOpen
    }

    @objc private func applicationDidActivate(_ notification: Notification) {
        applicationActivationHandler?()
    }
}
