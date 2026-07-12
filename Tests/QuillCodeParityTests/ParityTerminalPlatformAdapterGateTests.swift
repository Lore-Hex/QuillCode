import XCTest

final class ParityTerminalPlatformAdapterGateTests: QuillCodeParityTestCase {
    func testTerminalNativeInputStaysBehindPlatformAdapter() throws {
        let appText = try Self.swiftSourceFiles(in: "Sources/QuillCodeApp")
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        let adapterText = try Self.swiftSourceFiles(in: "Sources/QuillCodePlatformUI")
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
        let packageText = try String(
            contentsOf: Self.packageRoot().appendingPathComponent("Package.swift"),
            encoding: .utf8
        )

        Self.assertSource(appText, contains: "TerminalInputCaptureView")
        Self.assertSource(appText, excludes: "import AppKit")
        Self.assertSource(appText, excludes: "#if canImport(AppKit)")
        Self.assertSource(adapterText, contains: "import AppKit")
        Self.assertSource(adapterText, contains: "TerminalInputCaptureNSView")
        Self.assertSource(adapterText, contains: "override func scrollWheel")
        Self.assertSource(adapterText, contains: "override func keyDown")
        Self.assertSource(adapterText, contains: "TerminalMacKeyboardMapper")
        Self.assertSource(adapterText, contains: "handlePaste")
        Self.assertSource(packageText, contains: #".target(name: "QuillCodePlatformUI""#)
        Self.assertSource(packageText, contains: #""QuillCodePlatformUI""#)
    }

    func testTerminalKeyboardSequencesStayInProtocolLayer() throws {
        let keyboardInput = try Self.toolsSourceText(named: "TerminalKeyboardInput.swift")
        let adapterText = try Self.swiftSourceFiles(in: "Sources/QuillCodePlatformUI")
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")

        Self.assertSource(keyboardInput, contains: "TerminalKeyboardInputEncoder")
        Self.assertSource(keyboardInput, contains: "applicationCursorKeys")
        Self.assertSource(keyboardInput, contains: "bracketedPaste")
        Self.assertSource(adapterText, contains: "TerminalKeyboardInputRequest")
        Self.assertSource(adapterText, excludes: "\u{1B}[")
    }

    func testTerminalWheelQuantizationStaysInProtocolLayer() throws {
        let accumulator = try Self.toolsSourceText(named: "TerminalScrollWheelAccumulator.swift")
        let adapterText = try Self.swiftSourceFiles(in: "Sources/QuillCodePlatformUI")
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")

        Self.assertSource(accumulator, contains: "defaultMaximumEventsPerUpdate")
        Self.assertSource(accumulator, contains: "eventKind(axis:")
        Self.assertSource(adapterText, contains: "TerminalScrollWheelAccumulator")
        Self.assertSource(adapterText, excludes: "\u{1B}[")
    }
}
