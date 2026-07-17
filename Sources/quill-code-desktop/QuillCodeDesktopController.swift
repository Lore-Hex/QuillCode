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
    let modelStateCoordinator: QuillCodeDesktopModelStateCoordinator
    let paneCoordinator: QuillCodeDesktopPaneCoordinator
    let workspaceActionCoordinator: QuillCodeDesktopWorkspaceActionCoordinator
    let terminalCoordinator: QuillCodeDesktopTerminalCoordinator
    let transcriptExportCoordinator: QuillCodeDesktopTranscriptExportCoordinator
    let worktreeCoordinator: QuillCodeDesktopWorktreeCoordinator
    let workflowRecordingCoordinator: QuillCodeDesktopWorkflowRecordingCoordinator
    let tasks = QuillCodeDesktopTaskCoordinator()
    // Retained here because UNUserNotificationCenter.delegate is weak; nil until the window installs it.
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
        workspaceRoot: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) {
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
        self.modelStateCoordinator = QuillCodeDesktopModelStateCoordinator()
        self.paneCoordinator = QuillCodeDesktopPaneCoordinator()
        self.workspaceActionCoordinator = QuillCodeDesktopWorkspaceActionCoordinator()
        self.terminalCoordinator = QuillCodeDesktopTerminalCoordinator()
        self.transcriptExportCoordinator = transcriptExportCoordinator
        self.worktreeCoordinator = QuillCodeDesktopWorktreeCoordinator()
        self.workflowRecordingCoordinator = QuillCodeDesktopWorkflowRecordingCoordinator()
        do {
            self.model = try bootstrap.makeModel()
        } catch {
            self.model = QuillCodeWorkspaceModel()
        }
        self.workspaceRoot = workspaceRoot
        modelStateCoordinator.ensureDefaultProject(on: model, workspaceRoot: workspaceRoot)
        self.computerUseCoordinator.install(on: model)
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
        let initialState = modelStateCoordinator.initialState(from: model)
        self.surface = initialState.surface
        self.draft = initialState.draft
        self.terminalDraft = initialState.terminalDraft
        self.browserAddressDraft = initialState.browserAddressDraft
        browserCoordinator.installSessionUpdateHandler(
            model: model,
            refresh: { [weak self] in self?.refresh() }
        )
        let browserCoordinator = self.browserCoordinator
        model.visibleBrowserToolOverride = { call, _ in
            await QuillCodeDesktopVisibleBrowserToolExecutor.execute(
                call,
                browserCoordinator: browserCoordinator
            )
        }
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

    /// Registers the Approve/Skip notification category and the delegate that routes a tapped action
    /// back into the workspace. Called once when the real window appears (never in headless smoke),
    /// and idempotent so repeated onAppear calls are no-ops.
    func installApprovalNotificationHandling() {
        guard approvalNotificationDelegate == nil else { return }
        // UNUserNotificationCenter.current() requires a real application bundle. In a bare-executable
        // context (the headless render smoke) it throws "bundleProxyForCurrentProcess is nil"; only the
        // packaged .app has a bundle identifier. Notifications can't be delivered without a bundle
        // anyway, so skip registration when there isn't one.
        guard Bundle.main.bundleIdentifier != nil else { return }
        let delegate = QuillCodeApprovalNotificationDelegate { [weak self] requestID, approve, threadID in
            self?.decideNotificationApproval(requestID: requestID, approve: approve, threadID: threadID)
        }
        approvalNotificationDelegate = delegate
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        center.setNotificationCategories([QuillCodeApprovalNotification.category])
    }

    /// Decides a blocked approval gate from a tapped notification action. Selects the gate's thread
    /// first (a notification may target a thread the user is not currently viewing), then routes through
    /// the SAME coordinator `runToolCardAction` path as the in-app tool card. Going through the one
    /// path (rather than a bare `Task` calling `decidePendingApproval`) means the notification decision
    /// serializes on that chat's `.send` slot exactly like the in-app decision, so two decisions for
    /// the same chat cannot interleave their resume/drain. A Skip still records unconditionally.
    func decideNotificationApproval(requestID: String, approve: Bool, threadID: UUID?) {
        if let threadID, model.selectedThread?.id != threadID {
            selectThread(threadID)
        }
        runToolCardAction(ToolCardActionSurface(
            title: approve ? "Approve" : "Skip",
            kind: approve ? .approve : .deny,
            requestID: requestID,
            style: approve ? .primary : .secondary
        ))
    }

    private func scheduleModelCatalogRefreshIfNeeded() {
        tasks.startIfIdle(.modelCatalogRefresh) { [weak self] in
            guard let self else { return }
            await modelCatalogRefreshCoordinator.refreshIfNeeded(
                on: model,
                refresh: { [weak self] in self?.refresh() }
            )
        }
    }

    private func scheduleTrustedRouterCreditsRefreshIfNeeded() {
        tasks.startIfIdle(.trustedRouterCreditsRefresh) { [weak self] in
            guard let self else { return }
            await trustedRouterCreditsCoordinator.refresh(
                on: model,
                refreshSurface: { [weak self] in self?.refresh() }
            )
        }
    }

    func refresh() {
        computerUseCoordinator.refreshStatus(on: model)
        modelStateCoordinator.refreshState(
            from: model,
            surface: &surface,
            draft: &draft,
            terminalDraft: &terminalDraft,
            browserAddressDraft: &browserAddressDraft,
            isComposerTaskRunning: tasks.isSendRunning(threadID: model.selectedThread?.id)
        )
    }
}
