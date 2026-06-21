#if canImport(AppKit) && canImport(ApplicationServices) && canImport(CoreGraphics)
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

public struct MacComputerUseBackend: ComputerUseBackend {
    public init() {}

    public var status: ComputerUseStatus {
        ComputerUseStatus.permissionStatus(
            screenRecordingGranted: CGPreflightScreenCaptureAccess(),
            accessibilityGranted: AXIsProcessTrusted()
        )
    }

    public func screenshot() async throws -> ComputerScreenshot {
        try requireScreenRecording()
        guard let image = CGDisplayCreateImage(CGMainDisplayID()) else {
            throw ComputerUseError.unavailable("Could not capture the main display.")
        }
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw ComputerUseError.unavailable("Could not encode the screenshot as PNG.")
        }
        return ComputerScreenshot(
            width: image.width,
            height: image.height,
            pngBase64: pngData.base64EncodedString()
        )
    }

    public func leftClick(x: Int, y: Int) async throws {
        try requireAccessibility()
        let point = CGPoint(x: x, y: y)
        guard
            let down = CGEvent(
                mouseEventSource: eventSource(),
                mouseType: .leftMouseDown,
                mouseCursorPosition: point,
                mouseButton: .left
            ),
            let up = CGEvent(
                mouseEventSource: eventSource(),
                mouseType: .leftMouseUp,
                mouseCursorPosition: point,
                mouseButton: .left
            )
        else {
            throw ComputerUseError.unavailable("Could not create click events.")
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    public func type(_ text: String) async throws {
        try requireAccessibility()
        for scalarView in text.unicodeScalars.map(String.init) {
            try postUnicode(scalarView)
        }
    }

    public func scroll(dx: Int, dy: Int) async throws {
        try requireAccessibility()
        guard let event = CGEvent(
            scrollWheelEvent2Source: eventSource(),
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(dy),
            wheel2: Int32(dx),
            wheel3: 0
        ) else {
            throw ComputerUseError.unavailable("Could not create scroll event.")
        }
        event.post(tap: .cghidEventTap)
    }

    public func moveCursor(x: Int, y: Int) async throws {
        try requireAccessibility()
        guard let event = CGEvent(
            mouseEventSource: eventSource(),
            mouseType: .mouseMoved,
            mouseCursorPosition: CGPoint(x: x, y: y),
            mouseButton: .left
        ) else {
            throw ComputerUseError.unavailable("Could not create cursor move event.")
        }
        event.post(tap: .cghidEventTap)
    }

    public func pressKey(_ key: String) async throws {
        try requireAccessibility()
        guard let keyCode = Self.keyCode(for: key) else {
            throw ComputerUseError.unavailable("Unsupported key: \(key).")
        }
        try postKey(keyCode)
    }

    private func requireScreenRecording() throws {
        guard CGPreflightScreenCaptureAccess() else {
            throw ComputerUseError.permissionDenied(
                "Grant Screen Recording to QuillCode in System Settings."
            )
        }
    }

    private func requireAccessibility() throws {
        guard AXIsProcessTrusted() else {
            throw ComputerUseError.permissionDenied(
                "Grant Accessibility to QuillCode in System Settings."
            )
        }
    }

    private func eventSource() -> CGEventSource? {
        CGEventSource(stateID: .hidSystemState)
    }

    private func postUnicode(_ text: String) throws {
        var characters = Array(text.utf16)
        guard
            let keyDown = CGEvent(
                keyboardEventSource: eventSource(),
                virtualKey: 0,
                keyDown: true
            ),
            let keyUp = CGEvent(
                keyboardEventSource: eventSource(),
                virtualKey: 0,
                keyDown: false
            )
        else {
            throw ComputerUseError.unavailable("Could not create text input events.")
        }
        characters.withUnsafeMutableBufferPointer { buffer in
            keyDown.keyboardSetUnicodeString(
                stringLength: buffer.count,
                unicodeString: buffer.baseAddress
            )
            keyUp.keyboardSetUnicodeString(
                stringLength: buffer.count,
                unicodeString: buffer.baseAddress
            )
        }
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func postKey(_ keyCode: CGKeyCode) throws {
        guard
            let keyDown = CGEvent(
                keyboardEventSource: eventSource(),
                virtualKey: keyCode,
                keyDown: true
            ),
            let keyUp = CGEvent(
                keyboardEventSource: eventSource(),
                virtualKey: keyCode,
                keyDown: false
            )
        else {
            throw ComputerUseError.unavailable("Could not create keyboard events.")
        }
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private static func keyCode(for key: String) -> CGKeyCode? {
        switch key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "return", "enter":
            return 36
        case "tab":
            return 48
        case "escape", "esc":
            return 53
        case "delete", "backspace":
            return 51
        case "space":
            return 49
        case "left", "arrowleft":
            return 123
        case "right", "arrowright":
            return 124
        case "down", "arrowdown":
            return 125
        case "up", "arrowup":
            return 126
        case "home":
            return 115
        case "end":
            return 119
        case "pageup", "page up":
            return 116
        case "pagedown", "page down":
            return 121
        default:
            return nil
        }
    }
}
#endif
