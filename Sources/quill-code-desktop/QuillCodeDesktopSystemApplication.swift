import AppKit
import Darwin
import Foundation

extension Notification.Name {
    static let quillCodeDesktopWillTerminateForRelaunch = Notification.Name(
        "QuillCodeDesktopWillTerminateForRelaunch"
    )
}

@MainActor
enum QuillCodeDesktopSystemApplication {
    static var isActive: Bool {
        NSApplication.shared.isActive
    }

    static func startDictation() {
        NSApp.sendAction(Selector(("startDictation:")), to: nil, from: nil)
    }

    static func terminateForUpdate() {
        // SwiftUI can defer or decline a normal termination while a sheet-driven async action still
        // owns the scene. The detached updater helper cannot proceed until this process is gone, so
        // synchronously finish durable lifecycle work, then retain a short, bounded fallback after
        // first allowing normal app shutdown to complete.
        NotificationCenter.default.post(
            name: .quillCodeDesktopWillTerminateForRelaunch,
            object: nil
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            Darwin.exit(EXIT_SUCCESS)
        }
        NSApplication.shared.terminate(nil)
    }
}
