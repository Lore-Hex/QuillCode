import Foundation
import SwiftUI
import UserNotifications
import QuillCodeApp
import QuillCodeCore
import QuillCodeTools

@MainActor
final class QuillCodeDesktopController: ObservableObject {
    @Published var surface: WorkspaceSurface
    @Published var draft: String
    @Published var terminalDraft: String
    @Published var browserAddressDraft: String
    @Published var isCommandPalettePresented = false
    @Published var isSettingsPresented = false
    @Published var isKeyboardShortcutsPresented = false
    @Published var isSearchPresented = false
    @Published var isFindPresented = false
    @Published var isModelPickerPresented = false
    @Published var isProjectImporterPresented = false
    @Published var isImageImporterPresented = false
    @Published var copiedTranscriptItemID: String?

    let model: QuillCodeWorkspaceModel
    let bootstrap: QuillCodeWorkspaceBootstrap
    let computerUseCoordinator: QuillCodeDesktopComputerUseCoordinator
    let activeWorkCoordinator: QuillCodeDesktopActiveWorkCoordinator
    let browserCoordinator: QuillCodeDesktopBrowserCoordinator
    let automationCoordinator: QuillCodeDesktopAutomationCoordinator
    let automationNotifier: any QuillCodeAutomationNotifying
    let workspaceRoot: URL
    let navigationCoordinator: QuillCodeDesktopNavigationCoordinator
    let commandCoordinator: QuillCodeDesktopCommandCoordinator
    let signInCoordinator: QuillCodeDesktopSignInCoordinator
    let settingsCoordinator: QuillCodeDesktopSettingsCoordinator
    let modelCatalogRefreshCoordinator: QuillCodeDesktopModelCatalogRefreshCoordinator
    let trustedRouterCreditsCoordinator: QuillCodeDesktopTrustedRouterCreditsCoordinator
    let sshHostDiscovery: SSHHostDiscovery
    let sshRemoteProjectProbe: SSHRemoteProjectProbe
    let composerCoordinator: QuillCodeDesktopComposerCoordinator
    let copyCoordinator: QuillCodeDesktopCopyCoordinator
    let projectImportCoordinator: QuillCodeDesktopProjectImportCoordinator
    let projectAccessCoordinator: QuillCodeDesktopProjectAccessCoordinator
    let modelStateCoordinator: QuillCodeDesktopModelStateCoordinator
    let paneCoordinator: QuillCodeDesktopPaneCoordinator
    let workspaceActionCoordinator: QuillCodeDesktopWorkspaceActionCoordinator
    let terminalCoordinator: QuillCodeDesktopTerminalCoordinator
    let transcriptExportCoordinator: QuillCodeDesktopTranscriptExportCoordinator
    let worktreeCoordinator: QuillCodeDesktopWorktreeCoordinator
    let workflowRecordingCoordinator: QuillCodeDesktopWorkflowRecordingCoordinator
    let updateController: QuillCodeDesktopUpdateController
    let installationLocationController: QuillCodeDesktopInstallationLocationController
    let launchLifecycleController: QuillCodeDesktopLaunchLifecycleController?
    let tasks = QuillCodeDesktopTaskCoordinator()
    let progressRefreshScheduler = QuillCodeDesktopProgressRefreshScheduler()
    // Retained here because UNUserNotificationCenter.delegate is weak; nil until app services start.
    private var approvalNotificationDelegate: QuillCodeApprovalNotificationDelegate?

    init(
        bootstrap: QuillCodeWorkspaceBootstrap = QuillCodeWorkspaceBootstrap(),
        browserPageFetcher: any BrowserPageFetching = URLSessionBrowserPageFetcher(),
        browserLiveDOMCapturer: (any BrowserLiveDOMCapturing)? = DesktopBrowserLiveDOMCapturer(),
        browserSessionPresenter: any DesktopBrowserSessionPresenting = DesktopBrowserSessionPresenter(),
        automationNotifier: any QuillCodeAutomationNotifying = DesktopAutomationNotifierFactory.platformDefault(),
        sshHostDiscovery: SSHHostDiscovery = SSHHostDiscovery(),
        sshRemoteProjectProbe: SSHRemoteProjectProbe = SSHRemoteProjectProbe(),
        transcriptExportCoordinator: QuillCodeDesktopTranscriptExportCoordinator =
            QuillCodeDesktopTranscriptExportCoordinator(),
        updateController: QuillCodeDesktopUpdateController? = nil,
        installationLocationController: QuillCodeDesktopInstallationLocationController? = nil,
        launchLifecycleController: QuillCodeDesktopLaunchLifecycleController? = nil,
        workspaceRoot: URL? = nil
    ) {
        let launchWorkspaceRoot = workspaceRoot?.standardizedFileURL
        self.bootstrap = bootstrap
        self.computerUseCoordinator = QuillCodeDesktopComputerUseCoordinator()
        self.activeWorkCoordinator = QuillCodeDesktopActiveWorkCoordinator()
        self.browserCoordinator = QuillCodeDesktopBrowserCoordinator(
            pageFetcher: browserPageFetcher,
            liveDOMCapturer: browserLiveDOMCapturer,
            sessionPresenter: browserSessionPresenter
        )
        self.automationCoordinator = QuillCodeDesktopAutomationCoordinator()
        self.automationNotifier = automationNotifier
        self.navigationCoordinator = QuillCodeDesktopNavigationCoordinator()
        self.commandCoordinator = QuillCodeDesktopCommandCoordinator()
        self.signInCoordinator = QuillCodeDesktopSignInCoordinator(bootstrap: bootstrap)
        self.settingsCoordinator = QuillCodeDesktopSettingsCoordinator(bootstrap: bootstrap)
        self.modelCatalogRefreshCoordinator = QuillCodeDesktopModelCatalogRefreshCoordinator(bootstrap: bootstrap)
        self.trustedRouterCreditsCoordinator = QuillCodeDesktopTrustedRouterCreditsCoordinator(bootstrap: bootstrap)
        self.sshHostDiscovery = sshHostDiscovery
        self.sshRemoteProjectProbe = sshRemoteProjectProbe
        self.composerCoordinator = QuillCodeDesktopComposerCoordinator()
        self.copyCoordinator = QuillCodeDesktopCopyCoordinator()
        self.projectImportCoordinator = QuillCodeDesktopProjectImportCoordinator()
        self.projectAccessCoordinator = QuillCodeDesktopProjectAccessCoordinator()
        self.modelStateCoordinator = QuillCodeDesktopModelStateCoordinator()
        self.paneCoordinator = QuillCodeDesktopPaneCoordinator()
        self.workspaceActionCoordinator = QuillCodeDesktopWorkspaceActionCoordinator()
        self.terminalCoordinator = QuillCodeDesktopTerminalCoordinator()
        self.transcriptExportCoordinator = transcriptExportCoordinator
        self.worktreeCoordinator = QuillCodeDesktopWorktreeCoordinator()
        self.workflowRecordingCoordinator = QuillCodeDesktopWorkflowRecordingCoordinator()
        self.updateController = updateController ?? QuillCodeDesktopUpdateController()
        self.installationLocationController = installationLocationController
            ?? QuillCodeDesktopInstallationLocationController()
        self.launchLifecycleController = launchLifecycleController
        do {
            self.model = try bootstrap.makeModel()
        } catch {
            self.model = QuillCodeWorkspaceModel(
                startupLoadIssue: WorkspaceStartupLoadIssue(
                    loadedThreadCount: 0,
                    unreadableDataKinds: [.workspaceStorage]
                )
            )
        }
        self.workspaceRoot = launchWorkspaceRoot
            ?? FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        if let launchWorkspaceRoot {
            modelStateCoordinator.ensureDefaultProject(on: model, workspaceRoot: launchWorkspaceRoot)
        }
        self.computerUseCoordinator.install(on: model)
        // Opt-in (QUILLCODE_USE_CUA_DRIVER=1): asynchronously upgrade to the cua-driver backend so
        // computer use runs in the background without stealing focus/cursor. Native stays live until
        // this resolves, so startup never blocks on the driver subprocess.
        let cuaCoordinator = self.computerUseCoordinator
        let cuaModel = model
        Task { @MainActor in
            await cuaCoordinator.resolvePreferredBackend(on: cuaModel)
        }
        // Ping the user when unattended work needs attention. The closure reads live config so
        // Settings toggles apply immediately without rebuilding the desktop controller.
        let workspaceModel = model
        workspaceModel.onRunNotification = { [weak workspaceModel, automationNotifier] notification in
            guard let preferences = workspaceModel?.root.config.notificationPreferences else { return }
            guard DesktopNotificationPolicy.shouldDeliverAgentRun(
                preferences: preferences,
                appIsActive: QuillCodeDesktopSystemApplication.isActive
            ) else { return }
            automationNotifier.deliver(notification)
        }
        // Destroying an ephemeral (confidential) thread must cancel its OWNING send task, not just the
        // model's run-registry entry — otherwise provider calls and tools keep executing after the
        // UI promised the session was gone. (The side-conversation cancel helper doesn't cover
        // confidential: it keys off the side-conversation parent.)
        workspaceModel.onEphemeralThreadDiscarded = { [tasks] threadID in
            tasks.cancel(.send(threadID))
            // A current-thread code review occupies its own task slot; its reviewer provider call
            // and read tools must stop with the session too.
            tasks.cancel(.codeReview(threadID))
        }
        projectAccessCoordinator.restoreAccess(for: workspaceModel.root.projects)
        ToolArtifactLocalPreviewAccess.configure(
            projectRoots: workspaceModel.root.projects
                .filter { !$0.isRemote }
                .map { URL(fileURLWithPath: $0.path) },
            readableProjectRoots: projectAccessCoordinator.activeProjectURLs
        )
        let initialState = modelStateCoordinator.initialState(from: model)
        self.surface = initialState.surface
        self.draft = initialState.draft
        self.terminalDraft = initialState.terminalDraft
        self.browserAddressDraft = initialState.browserAddressDraft
        workspaceModel.onFileMentionIndexChanged = { [weak self] in
            self?.refresh()
        }
        workspaceModel.onProjectContextChanged = { [weak self] in
            self?.refresh()
        }
        workspaceModel.scheduleSelectedProjectContextRefresh()
        // Bootstrap may finish a very small scan before the callback above is installed. Starting
        // one final generation here guarantees the published surface receives the completed index.
        workspaceModel.refreshFileMentionIndex()
        browserCoordinator.installSessionUpdateHandler(
            model: model,
            refresh: { [weak self] in self?.refresh() }
        )
        installVisibleBrowserToolOverride(on: model)
        automationCoordinator.runDueAutomations(
            model: model,
            notifier: automationNotifier,
            refresh: { [weak self] in self?.refresh() }
        )
        automationCoordinator.startTicker(
            model: model,
            tasks: tasks,
            notifier: automationNotifier,
            refresh: { [weak self] in self?.refresh() }
        )
        scheduleModelCatalogRefreshIfNeeded()
        modelCatalogRefreshCoordinator.startTicker(tasks: tasks) { [weak self] in
            self?.scheduleModelCatalogRefreshIfNeeded()
        }
        scheduleTrustedRouterCreditsRefreshIfNeeded()
        trustedRouterCreditsCoordinator.startTicker(tasks: tasks) { [weak self] in
            self?.scheduleTrustedRouterCreditsRefreshIfNeeded()
        }
    }

    /// Starts services that belong to the application process rather than any SwiftUI scene. The
    /// ordinary app entry point calls this once; the owned controllers keep repeat calls idempotent.
    func startApplicationServices() {
        installApprovalNotificationHandling()
        installationLocationController.startIfNeeded()
        updateController.startAutomaticChecks()
    }

    /// Registers the Approve/Skip notification category and the delegate that routes a tapped action
    /// back into the workspace. This can run before a window exists and remains idempotent.
    private func installApprovalNotificationHandling() {
        guard approvalNotificationDelegate == nil else { return }
        // Only the packaged product owns these categories. Bare executables and XCTest bundles must
        // not replace the notification delegate of their host process.
        guard Bundle.main.bundleIdentifier == updateController.configuration?.bundleIdentifier else {
            return
        }
        let delegate = QuillCodeApprovalNotificationDelegate(
            onDecision: { [weak self] requestID, approve, threadID in
                self?.decideNotificationApproval(requestID: requestID, approve: approve, threadID: threadID)
            },
            onRetry: { [weak self] threadID in self?.retryFailedRunFromNotification(threadID: threadID) }
        )
        approvalNotificationDelegate = delegate
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        center.setNotificationCategories([QuillCodeApprovalNotification.category, QuillCodeRetryNotification.category])
    }

}
