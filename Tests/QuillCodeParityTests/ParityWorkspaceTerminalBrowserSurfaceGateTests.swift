import XCTest

final class ParityWorkspaceTerminalBrowserSurfaceGateTests: QuillCodeParityTestCase {
    func testNativeTerminalAndBrowserPanesUseFocusedViewFiles() throws {
        let appRoot = Self.packageRoot().appendingPathComponent("Sources/QuillCodeApp")
        for fileName in [
            "QuillCodeTerminalPaneView.swift",
            "QuillCodeTerminalEntryView.swift",
            "QuillCodeBrowserPaneView.swift"
        ] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: appRoot.appendingPathComponent(fileName).path))
        }
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: appRoot.appendingPathComponent("QuillCodeTerminalBrowserPaneView.swift").path
            )
        )

        let terminalText = try Self.appSourceText(named: "QuillCodeTerminalPaneView.swift")
        let terminalEntryText = try Self.appSourceText(named: "QuillCodeTerminalEntryView.swift")
        let browserText = try Self.appSourceText(named: "QuillCodeBrowserPaneView.swift")

        Self.assertSource(terminalText, contains: "struct QuillCodeTerminalPaneView")
        Self.assertSource(terminalText, contains: "QuillCodeTerminalEntryView")
        Self.assertSource(terminalEntryText, contains: "struct QuillCodeTerminalEntryView")
        Self.assertSource(browserText, contains: "struct QuillCodeBrowserPaneView")
        Self.assertSource(terminalText, excludes: "struct QuillCodeBrowserPaneView")
        Self.assertSource(browserText, excludes: "struct QuillCodeTerminalPaneView")
    }

    func testWorkspaceSurfaceDelegatesTerminalSurfaceContracts() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let terminalText = try Self.appSourceText(named: "QuillCodeTerminalSurface.swift")

        [
            "public struct TerminalSurface",
            "public struct TerminalCommandSurface",
            "TerminalCommandState",
            "ExecutionContextSurface?"
        ].forEach { Self.assertSource(terminalText, contains: $0) }

        Self.assertSource(surfaceText, excludes: "public struct TerminalSurface")
        Self.assertSource(surfaceText, excludes: "public struct TerminalCommandSurface")
    }

    func testTerminalStateContractsLiveOutsideEngine() throws {
        let engineText = try Self.appSourceText(named: "WorkspaceTerminalEngine.swift")
        let stateText = try Self.appSourceText(named: "WorkspaceTerminalState.swift")
        let adapterText = try Self.appSourceText(named: "WorkspaceTerminalSessionAdapter.swift")

        [
            "public struct TerminalCommandState",
            "public enum TerminalCommandStatus",
            "public struct TerminalState",
            "struct WorkspaceTerminalExecutionContext",
            "struct WorkspaceTerminalSessionResult"
        ].forEach { Self.assertSource(stateText, contains: $0) }

        [
            "enum WorkspaceTerminalSessionAdapter",
            "static func localExecutionContext",
            "static func remoteWrappedCommand",
            "static func sessionResult",
            "static func remoteMetadata",
            "static func remoteEnvironmentDelta",
            "private static func environment(fromHex",
            "nonisolated static func shellSingleQuoted"
        ].forEach { Self.assertSource(adapterText, contains: $0) }

        Self.assertSource(engineText, contains: "enum WorkspaceTerminalEngine")
        Self.assertSource(engineText, contains: "WorkspaceTerminalSessionAdapter.sessionResult")

        [
            "public struct TerminalCommandState",
            "public enum TerminalCommandStatus",
            "public struct TerminalState",
            "struct WorkspaceTerminalExecutionContext",
            "struct WorkspaceTerminalSessionResult",
            "static func localExecutionContext",
            "static func remoteWrappedCommand",
            "struct RemoteTerminalMetadata",
            "environment(fromHex"
        ].forEach { Self.assertSource(engineText, excludes: $0) }
    }
}
