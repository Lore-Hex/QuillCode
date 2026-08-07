import AppKit
import Darwin

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
        // retain a short, bounded fallback after first allowing normal app shutdown to complete.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            Darwin.exit(EXIT_SUCCESS)
        }
        NSApplication.shared.terminate(nil)
    }
}
