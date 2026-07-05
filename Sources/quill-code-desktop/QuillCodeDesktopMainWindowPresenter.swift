import AppKit
import SwiftUI

@MainActor
final class QuillCodeDesktopMainWindowPresenter: NSObject, NSWindowDelegate {
    static let shared = QuillCodeDesktopMainWindowPresenter()

    private var window: NSWindow?
    private var launchObserver: NSObjectProtocol?

    func scheduleLaunch(controller: QuillCodeDesktopController) {
        NSApplication.shared.setActivationPolicy(.regular)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            show(controller: controller)
        }
        launchObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil,
            queue: .main
        ) { [weak self, weak controller] _ in
            guard let self, let controller else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 250_000_000)
                self.show(controller: controller)
            }
        }
    }

    func show(controller: QuillCodeDesktopController) {
        let window = existingWindow ?? makeWindow(controller: controller)
        placeOnPrimaryVisibleScreen(window)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_: Notification) {
        window = nil
    }

    private var existingWindow: NSWindow? {
        if let window, window.isVisible {
            return window
        }
        return NSApplication.shared.windows.first {
            $0.title == "QuillCode" && $0.isVisible
        }
    }

    private func makeWindow(controller: QuillCodeDesktopController) -> NSWindow {
        let rootView = QuillCodeDesktopRootView(controller: controller)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "QuillCode"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.contentView = NSHostingView(rootView: rootView)
        placeOnPrimaryVisibleScreen(window)
        window.delegate = self
        window.isReleasedWhenClosed = false
        self.window = window
        return window
    }

    private func placeOnPrimaryVisibleScreen(_ window: NSWindow) {
        let screen = NSScreen.screens.first { screen in
            screen.frame.origin == .zero
        } ?? NSScreen.main ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else { return }

        let width = min(CGFloat(1280), visibleFrame.width - 80)
        let height = min(CGFloat(900), visibleFrame.height - 80)
        let frame = NSRect(
            x: visibleFrame.minX + 40,
            y: visibleFrame.maxY - height - 40,
            width: max(900, width),
            height: max(640, height)
        )
        window.setFrame(frame, display: true)
    }
}
