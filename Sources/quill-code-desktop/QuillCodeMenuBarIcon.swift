import AppKit

enum QuillCodeMenuBarIcon {
    static var image: NSImage {
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
            accessibilityDescription: "QuillCode"
        ) ?? NSImage(size: NSSize(width: 18, height: 18))
        fallback.isTemplate = true
        return fallback
    }
}
