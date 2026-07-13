import XCTest

class QuillCodeParityTestCase: XCTestCase {
    static func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    static func swiftSourceFiles(in relativePath: String) throws -> [URL] {
        let root = packageRoot().appendingPathComponent(relativePath)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        return enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.path < $1.path }
    }

    static func desktopSourceText() throws -> String {
        let root = packageRoot().appendingPathComponent("Sources/quill-code-desktop")
        return try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "swift" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .map { try String(contentsOf: $0, encoding: .utf8) }
        .joined(separator: "\n")
    }

    static func desktopSourceText(named fileName: String) throws -> String {
        let file = packageRoot()
            .appendingPathComponent("Sources/quill-code-desktop")
            .appendingPathComponent(fileName)
        return try String(contentsOf: file, encoding: .utf8)
    }

    static func desktopTestSourceText(named fileName: String) throws -> String {
        let file = packageRoot()
            .appendingPathComponent("Tests/QuillCodeDesktopTests")
            .appendingPathComponent(fileName)
        return try String(contentsOf: file, encoding: .utf8)
    }

    static func desktopControllerSourceText() throws -> String {
        let root = packageRoot().appendingPathComponent("Sources/quill-code-desktop")
        return try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        )
        .filter {
            $0.pathExtension == "swift"
                && $0.lastPathComponent.hasPrefix("QuillCodeDesktopController")
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .map { try String(contentsOf: $0, encoding: .utf8) }
        .joined(separator: "\n")
    }

    static func appSourceText(named fileName: String) throws -> String {
        let file = packageRoot()
            .appendingPathComponent("Sources/QuillCodeApp")
            .appendingPathComponent(fileName)
        return try String(contentsOf: file, encoding: .utf8)
    }

    static func appTestSourceText(named fileName: String) throws -> String {
        let file = packageRoot()
            .appendingPathComponent("Tests/QuillCodeAppTests")
            .appendingPathComponent(fileName)
        return try String(contentsOf: file, encoding: .utf8)
    }

    static func agentTestSourceText(named fileName: String) throws -> String {
        let file = packageRoot()
            .appendingPathComponent("Tests/QuillCodeAgentTests")
            .appendingPathComponent(fileName)
        return try String(contentsOf: file, encoding: .utf8)
    }

    static func parityTestSourceText(named fileName: String) throws -> String {
        let file = packageRoot()
            .appendingPathComponent("Tests/QuillCodeParityTests")
            .appendingPathComponent(fileName)
        return try String(contentsOf: file, encoding: .utf8)
    }

    static func agentSourceText(named fileName: String) throws -> String {
        let file = packageRoot()
            .appendingPathComponent("Sources/QuillCodeAgent")
            .appendingPathComponent(fileName)
        return try String(contentsOf: file, encoding: .utf8)
    }

    static func coreSourceText(named fileName: String) throws -> String {
        let file = packageRoot()
            .appendingPathComponent("Sources/QuillCodeCore")
            .appendingPathComponent(fileName)
        return try String(contentsOf: file, encoding: .utf8)
    }

    static var generalDomainModelSourceFiles: [String] {
        [
            "AgentMode.swift",
            "ChatModels.swift",
            "AgentPlanModels.swift",
            "SubagentModels.swift",
            "ApprovalModels.swift",
            "ThreadEventModels.swift",
            "MemoryModels.swift",
            "ChatThread.swift",
            "JSONHelpers.swift"
        ]
    }

    static func generalDomainModelsText() throws -> String {
        try generalDomainModelSourceFiles
            .map { try coreSourceText(named: $0) }
            .joined(separator: "\n")
    }

    static func assertLegacyGeneralModelsFileIsRetired(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let legacyFile = packageRoot()
            .appendingPathComponent("Sources/QuillCodeCore")
            .appendingPathComponent("Models.swift")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: legacyFile.path),
            "General model records should stay in focused source files; do not reintroduce Models.swift.",
            file: file,
            line: line
        )
    }

    static func assertSource(
        _ source: String,
        contains expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            source.contains(expected),
            "Expected source to contain: \(expected)",
            file: file,
            line: line
        )
    }

    static func assertSource(
        _ source: String,
        containsAll expectedValues: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for expected in expectedValues {
            assertSource(source, contains: expected, file: file, line: line)
        }
    }

    static func assertSource(
        _ source: String,
        excludes forbidden: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(
            source.contains(forbidden),
            "Expected source to exclude: \(forbidden)",
            file: file,
            line: line
        )
    }

    static func assertSource(
        _ source: String,
        excludesAll forbiddenValues: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for forbidden in forbiddenValues {
            assertSource(source, excludes: forbidden, file: file, line: line)
        }
    }

    static func toolsSourceText(named fileName: String) throws -> String {
        let file = packageRoot()
            .appendingPathComponent("Sources/QuillCodeTools")
            .appendingPathComponent(fileName)
        return try String(contentsOf: file, encoding: .utf8)
    }

    static func toolsTestSourceText(named fileName: String) throws -> String {
        let file = packageRoot()
            .appendingPathComponent("Tests/QuillCodeToolsTests")
            .appendingPathComponent(fileName)
        return try String(contentsOf: file, encoding: .utf8)
    }

    static func docsText(named fileName: String) throws -> String {
        let file = packageRoot()
            .appendingPathComponent("docs")
            .appendingPathComponent(fileName)
        return try String(contentsOf: file, encoding: .utf8)
    }

    static func nativeClickProbeValidatorText() throws -> String {
        let validatorRoot = packageRoot()
            .appendingPathComponent("scripts")
            .appendingPathComponent("native_click_probe_contracts")
        let packageFiles = try FileManager.default.contentsOfDirectory(
            at: validatorRoot,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "py" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .map { try String(contentsOf: $0, encoding: .utf8) }

        let entrypoint = try String(
            contentsOf: self.packageRoot()
                .appendingPathComponent("scripts")
                .appendingPathComponent("native-click-probe-contracts.py"),
            encoding: .utf8
        )
        return ([entrypoint] + packageFiles).joined(separator: "\n")
    }

    static func liveTrustedRouterSmokeText() throws -> String {
        let helperRoot = packageRoot()
            .appendingPathComponent("scripts")
            .appendingPathComponent("live_tr_smoke")
        let helperFiles = try FileManager.default.contentsOfDirectory(
            at: helperRoot,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "sh" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .map { try String(contentsOf: $0, encoding: .utf8) }

        let entrypoint = try String(
            contentsOf: self.packageRoot()
                .appendingPathComponent("scripts")
                .appendingPathComponent("live-tr-smoke.sh"),
            encoding: .utf8
        )
        return ([entrypoint] + helperFiles).joined(separator: "\n")
    }

    static func safetySourceText(named fileName: String) throws -> String {
        let file = packageRoot()
            .appendingPathComponent("Sources/QuillCodeSafety")
            .appendingPathComponent(fileName)
        return try String(contentsOf: file, encoding: .utf8)
    }

    static func safetyTestSourceText(named fileName: String) throws -> String {
        let file = packageRoot()
            .appendingPathComponent("Tests/QuillCodeSafetyTests")
            .appendingPathComponent(fileName)
        return try String(contentsOf: file, encoding: .utf8)
    }
}
