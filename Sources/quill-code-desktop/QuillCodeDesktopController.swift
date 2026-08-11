import Foundation
import SwiftUI
import UserNotifications
import QuillCodeApp
import QuillCodeCore
import QuillCodeTools

@MainActor
final class QuillCodeDesktopController: ObservableObject {
    @Published var surface: WorkspaceSurface
    @Published var draft: String {
        didSet {
            guard !isComposerDraftBindingSideEffectsSuppressed else { return }
            let ownerThreadID = model.selectedThread?.id
            composerDraftCheckpointCoordinator.schedule(draft: draft, model: model)
            model.updateLiveComposerDraft(draft, ownerThreadID: ownerThreadID)
        }
    }
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
    let composerDraftCheckpointCoordinator: QuillCodeDesktopComposerDraftCheckpointCoordinator
    var isComposerDraftBindingSideEffectsSuppressed = false
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
    var automaticStartupState: QuillCodeDesktopStartupState
    // Retained here because UNUserNotificationCenter.delegate is weak; nil until app services start.
    private var approvalNotificationDelegate: QuillCodeApprovalNotificationDelegate?

    init(
        bootstrap: QuillCodeWorkspaceBootstrap = QuillCodeWorkspaceBootstrap(),
        computerUseCoordinator: QuillCodeDesktopComputerUseCoordinator =
            QuillCodeDesktopComputerUseCoordinator(),
        browserPageFetcher: any BrowserPageFetching = URLSessionBrowserPageFetcher(),
        browserLiveDOMCapturer: (any BrowserLiveDOMCapturing)? = DesktopBrowserLiveDOMCapturer(),
        browserSessionPresenter: any DesktopBrowserSessionPresenting = DesktopBrowserSessionPresenter(),
        automationNotifier: any QuillCodeAutomationNotifying = DesktopAutomationNotifierFactory.platformDefault(),
        sshHostDiscovery: SSHHostDiscovery = SSHHostDiscovery(),
        sshRemoteProjectProbe: SSHRemoteProjectProbe = SSHRemoteProjectProbe(),
        composerDraftCheckpointCoordinator: QuillCodeDesktopComposerDraftCheckpointCoordinator =
            QuillCodeDesktopComposerDraftCheckpointCoordinator(),
        projectAccessCoordinator: QuillCodeDesktopProjectAccessCoordinator =
            QuillCodeDesktopProjectAccessCoordinator(),
        transcriptExportCoordinator: QuillCodeDesktopTranscriptExportCoordinator =
            QuillCodeDesktopTranscriptExportCoordinator(),
        updateController: QuillCodeDesktopUpdateController? = nil,
        installationLocationController: QuillCodeDesktopInstallationLocationController? = nil,
        launchLifecycleController: QuillCodeDesktopLaunchLifecycleController? = nil,
        startupMode: QuillCodeDesktopStartupMode = .normal,
        workspaceRoot: URL? = nil
    ) {
        let launchWorkspaceRoot = workspaceRoot?.standardizedFileURL
        self.bootstrap = bootstrap
        self.computerUseCoordinator = computerUseCoordinator
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
        self.composerDraftCheckpointCoordinator = composerDraftCheckpointCoordinator
        self.copyCoordinator = QuillCodeDesktopCopyCoordinator()
        self.projectImportCoordinator = QuillCodeDesktopProjectImportCoordinator()
        self.projectAccessCoordinator = projectAccessCoordinator
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
        self.automaticStartupState = QuillCodeDesktopStartupState(mode: startupMode)
        do {
            self.model = try bootstrap.makeModel(automaticStartupPolicy: .deferUntilRequested)
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
        workspaceModel.onFileMentionIndexChanged = { [weak self] in
            self?.refresh()
        }
        workspaceModel.onProjectContextChanged = { [weak self] in
            self?.refresh()
        }
        browserCoordinator.installSessionUpdateHandler(
            model: model,
            refresh: { [weak self] in self?.refresh() }
        )
        installVisibleBrowserToolOverride(on: model)
    }

    /// Starts process-owned services after SwiftUI has yielded through the first-window boundary.
    /// The owned controllers keep repeat calls idempotent for recovery and repeated scene tasks.
    func startApplicationServicesAfterFirstWindow() {
        composerDraftCheckpointCoordinator.startLifecycleFlushes(model: model)
        installApprovalNotificationHandling()
        installationLocationController.startIfNeeded()
        updateController.startAutomaticChecks()
    }

    /// Registers the Approve/Skip notification category and the delegate that routes a tapped action
    /// back into the workspace. It remains idempotent across repeated post-window startup requests.
    private func installApprovalNotificationHandling() {
        guard approvalNotificationDelegate == nil else { return }
        let bundle = Bundle.main
        // A SwiftPM executable can inherit the product bundle identifier without being backed by a
        // Launch Services bundle. UserNotifications raises an Objective-C exception in that state,
        // so identity and the canonical packaged layout must agree before touching the singleton.
        guard QuillCodeDesktopPackagedProcessIdentity.ownsNotificationCenter(
            bundleIdentifier: bundle.bundleIdentifier,
            bundleURL: bundle.bundleURL,
            executableURL: bundle.executableURL,
            expectedBundleIdentifier: updateController.configuration?.bundleIdentifier
        ) else {
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

enum QuillCodeDesktopPackagedProcessIdentity {
    static func ownsNotificationCenter(
        bundleIdentifier: String?,
        bundleURL: URL,
        executableURL: URL?,
        expectedBundleIdentifier: String?
    ) -> Bool {
        guard let expectedBundleIdentifier,
              bundleIdentifier == expectedBundleIdentifier,
              bundleURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
              let executableURL
        else {
            return false
        }
        let expectedExecutableDirectory = bundleURL
            .appendingPathComponent("Contents/MacOS", isDirectory: true)
            .standardizedFileURL
        return executableURL
            .deletingLastPathComponent()
            .standardizedFileURL == expectedExecutableDirectory
    }
}
