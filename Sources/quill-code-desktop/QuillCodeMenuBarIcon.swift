import AppKit
import QuillCodeApp

enum QuillCodeMenuBarIcon {
    // SwiftUI may evaluate the MenuBarExtra label frequently. Load the bundled bitmap once so
    // those body passes never perform synchronous filesystem metadata work on the main thread.
    static let image: NSImage = {
        if let url = Bundle.main.url(
            forResource: "QuillCodeMenuBarTemplate",
            withExtension: "png"
        ),
            let image = NSImage(contentsOf: url) {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            return image
        }

        let fallback = NSImage(
            systemSymbolName: "q.circle.fill",
            accessibilityDescription: QuillCodeProduct.displayName
        ) ?? NSImage(size: NSSize(width: 18, height: 18))
        fallback.isTemplate = true
        return fallback
    }()
}
