import AppKit

@MainActor
enum QuillCodeDesktopSystemApplication {
    static var isActive: Bool {
        NSApplication.shared.isActive
    }

    static func startDictation() {
        NSApp.sendAction(Selector(("startDictation:")), to: nil, from: nil)
    }
}
