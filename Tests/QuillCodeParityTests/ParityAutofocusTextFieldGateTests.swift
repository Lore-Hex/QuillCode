import XCTest

final class ParityAutofocusTextFieldGateTests: QuillCodeParityTestCase {
    func testAutofocusTextFieldStaysBoundedCancellableAndNative() throws {
        let fieldURL = try XCTUnwrap(
            Self.swiftSourceFiles(in: "Sources/QuillCodePlatformUI")
                .first { $0.lastPathComponent == "QuillCodeAutofocusTextField.swift" }
        )
        let fieldText = try String(contentsOf: fieldURL, encoding: .utf8)

        for expected in [
            "public struct QuillCodeAutofocusTextField: View",
            "private struct PlatformAutofocusTextField: NSViewRepresentable",
            "private final class QuillCodeAutofocusNativeTextField: NSTextField",
            "private static let maximumAttempts = 20",
            "private static let retryInterval = Duration.milliseconds(50)",
            "focusTask?.cancel()",
            "guard !Task.isCancelled",
            "window.makeFirstResponder(self)",
            "func controlTextDidChange",
            "doCommandBy commandSelector: Selector",
            "parent.onSubmit()",
            "parent.onCancel()"
        ] {
            Self.assertSource(fieldText, contains: expected)
        }
        for excluded in [
            "AXUIElementCreateApplication",
            "DispatchQueue.main.asyncAfter",
            "Timer."
        ] {
            Self.assertSource(fieldText, excludes: excluded)
        }
    }
}
