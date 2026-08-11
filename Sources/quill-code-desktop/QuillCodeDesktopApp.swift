import AppKit
import Darwin
import SwiftUI
import QuillCodeApp

enum QuillCodeDesktopSceneID {
    static let mainWindow = "quillcode-main-window"
}

@main
struct QuillCodeDesktopApp: App {
    @StateObject private var controller: QuillCodeDesktopController

    init() {
        _ = QuillCodeDesktopLaunchClock.appEntryUptime
        QuillCodeDesktopUpdateLaunchHandshake.acknowledgeIfRequested()
        if let updateRequest = QuillCodeDesktopUpdateHelperRequest.parse(arguments: CommandLine.arguments) {
            Darwin.exit(QuillCodeDesktopUpdateHelper.run(updateRequest))
        }
        if let seedRequest = QuillCodeDesktopDailyDriverSmokeSeedRequest(arguments: CommandLine.arguments) {
            Darwin.exit(QuillCodeDesktopDailyDriverSmokeFixture.runAndReport(seedRequest))
        }

        if let relocationSmokeRequest = QuillCodeDesktopRelocationSmokeRequest(
            arguments: CommandLine.arguments
        ) {
            let controller = QuillCodeDesktopController(
                updateController: QuillCodeDesktopUpdateController(
                    configuration: nil,
                    installResultURL: nil
                ),
                installationLocationController: QuillCodeDesktopInstallationLocationController(
                    configuration: nil
                )
            )
            _controller = StateObject(wrappedValue: controller)
            Task { @MainActor in
                await QuillCodeDesktopRelocationSmokeRunner.runAndExit(relocationSmokeRequest)
            }
            return
        }

        if let updaterSmokeRequest = QuillCodeDesktopUpdaterSmokeRequest(
            arguments: CommandLine.arguments
        ) {
            let controller = QuillCodeDesktopController(
                updateController: QuillCodeDesktopUpdateController(
                    configuration: nil,
                    installResultURL: nil
                ),
                installationLocationController: QuillCodeDesktopInstallationLocationController(
                    configuration: nil
                )
            )
            _controller = StateObject(wrappedValue: controller)
            Task { @MainActor in
                await QuillCodeDesktopUpdaterSmokeRunner.runAndExit(updaterSmokeRequest)
            }
            return
        }

        // Quill Cowork is a dark-themed appliance: pin the whole app (every window, sheet, popover, and
        // system-drawn control) to the dark aqua appearance. Without this, system chrome — .roundedBorder
        // text fields, sheet/popover backgrounds, menu text — follows the user's macOS appearance, so on a
        // Light-mode Mac you get black text on our dark surfaces and "modal colors way off". One global
        // pin fixes that class of contrast bugs everywhere at once.
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)

        if let request = QuillCodeDesktopCoworkEvalRequest(arguments: CommandLine.arguments) {
            let controller = request.makeController()
            _controller = StateObject(wrappedValue: controller)
            Task { @MainActor in
                await QuillCodeDesktopCoworkEvalRunner.runAndExit(request, controller: controller)
            }
            return
        }

        if let request = QuillCodeDesktopComposerDraftCrashSmokeRequest(arguments: CommandLine.arguments) {
            let workspaceRoot = QuillCodeDesktopComposerDraftCrashSmokeWorkspaceRoot(request: request)
            let controller = workspaceRoot.makeController()
            _controller = StateObject(wrappedValue: controller)
            Task { @MainActor in
                await QuillCodeDesktopComposerDraftCrashSmoke.runAndExit(
                    request,
                    controller: controller,
                    workspaceRoot: workspaceRoot
                )
            }
            return
        }

        if let windowRequest = QuillCodeDesktopWindowSmokeRequest(arguments: CommandLine.arguments) {
            let workspaceRoot = QuillCodeDesktopWindowSmokeWorkspaceRoot(request: windowRequest)
            let controller = workspaceRoot.makeController()
            _controller = StateObject(wrappedValue: controller)
            QuillCodeDesktopWindowSmokeLaunch.schedule(
                windowRequest,
                controller: controller,
                workspaceRoot: workspaceRoot
            )
            return
        }

        if let request = QuillCodeDesktopSmokeRequest(arguments: CommandLine.arguments) {
            let controller: QuillCodeDesktopController
            if let workspaceRoot = try? QuillCodeDesktopSmokeWorkspaceRoot(request: request) {
                controller = workspaceRoot.makeLaunchController()
            } else {
                controller = QuillCodeDesktopController(
                    updateController: QuillCodeDesktopUpdateController(
                        configuration: nil,
                        installResultURL: nil
                    ),
                    installationLocationController: QuillCodeDesktopInstallationLocationController(
                        configuration: nil
                    ),
                    workspaceRoot: QuillCodeDesktopWorkspaceRootResolver.resolve()
                )
            }
            _controller = StateObject(wrappedValue: controller)
            Task { @MainActor in
                await QuillCodeDesktopLaunchRecoverySmoke.runAndExit(request)
            }
            return
        }

        let updateController = QuillCodeDesktopUpdateController()
        let launchLifecycleController = updateController.configuration.map { configuration in
            QuillCodeDesktopLaunchLifecycleController(
                metadata: QuillCodeDesktopBuildMetadata.current(configuration: configuration)
            )
        }
        let unexpectedExit = launchLifecycleController?.startIfNeeded()
        let controller = QuillCodeDesktopController(
            updateController: updateController,
            launchLifecycleController: launchLifecycleController,
            startupMode: QuillCodeDesktopStartupMode(unexpectedExit: unexpectedExit),
            workspaceRoot: QuillCodeDesktopWorkspaceRootResolver.resolve()
        )
        _controller = StateObject(wrappedValue: controller)
    }

    var body: some Scene {
        Window(QuillCodeProduct.displayName, id: QuillCodeDesktopSceneID.mainWindow) {
            QuillCodeDesktopRootView(controller: controller)
        }
        .defaultSize(width: 1280, height: 900)
        .windowStyle(.hiddenTitleBar)
        .commands {
            QuillCodeDesktopCommands(
                commands: controller.surface.commands,
                shortcutProfile: WorkspaceShortcutRegistry.profile(
                    preferences: controller.surface.settings.keyboardShortcuts
                ),
                onCommand: { controller.runCommand(commandID: $0) },
                onCheckForUpdates: controller.checkForUpdates,
                onReportIssue: controller.reportIssue
            )
        }
        MenuBarExtra {
            QuillCodeMenuBarView(
                surface: controller.surface,
                onNewChat: controller.newChat,
                onOpenProject: controller.requestAddProject,
                onCommandPalette: controller.openCommandPalette,
                onKeyboardShortcuts: controller.openKeyboardShortcuts,
                onSettings: controller.openSettings,
                onToggleTerminal: controller.toggleTerminal,
                onToggleBrowser: controller.toggleBrowser,
                onOpenBrowserSession: controller.openBrowserSession,
                onToggleExtensions: controller.toggleExtensions,
                onStopWorkflowRecording: controller.stopWorkflowRecording,
                onToggleMemories: controller.toggleMemories,
                onStopAll: controller.stopAll,
                onDisconnectAll: controller.disconnectAll,
                onComputerUseSetup: controller.openSettings,
                onCheckForUpdates: controller.checkForUpdates,
                onReportIssue: controller.reportIssue,
                onQuit: {
                    NSApplication.shared.terminate(nil)
                }
            )
        } label: {
            Image(nsImage: QuillCodeMenuBarIcon.image)
                .accessibilityLabel(QuillCodeProduct.displayName)
        }
    }
}

@MainActor
private enum QuillCodeDesktopWindowSmokeLaunch {
    private static var observer: NSObjectProtocol?

    static func schedule(
        _ request: QuillCodeDesktopWindowSmokeRequest,
        controller: QuillCodeDesktopController,
        workspaceRoot: QuillCodeDesktopWindowSmokeWorkspaceRoot
    ) {
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                if let observer {
                    NotificationCenter.default.removeObserver(observer)
                    Self.observer = nil
                }
                await QuillCodeDesktopWindowSmokeRunner.runAndExit(
                    request,
                    controller: controller,
                    workspaceRoot: workspaceRoot
                )
            }
        }
    }
}
