import Foundation
import QuillCodeApp
import QuillCodeCore
import QuillCodePersistence

struct QuillCodeDesktopCoworkEvalRequest: Sendable {
    static let exactModelID = "deepseek/deepseek-v4-flash-0731"

    var homePath: String
    var workspacePath: String
    var promptPath: String
    var reportPath: String?
    var browserPath: String?
    var modelID: String
    var timeoutSeconds: Int

    init?(arguments: [String]) {
        guard arguments.contains("--cowork-eval") else { return nil }

        let fallbackRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-cowork-eval-\(UUID().uuidString)", isDirectory: true)
        homePath = Self.value(after: "--cowork-eval-home", in: arguments)
            ?? fallbackRoot.appendingPathComponent("home", isDirectory: true).path
        workspacePath = Self.value(after: "--cowork-eval-workspace", in: arguments)
            ?? fallbackRoot.appendingPathComponent("workspace", isDirectory: true).path
        promptPath = Self.value(after: "--cowork-eval-prompt-file", in: arguments) ?? ""
        reportPath = Self.value(after: "--cowork-eval-report", in: arguments)
        browserPath = Self.value(after: "--cowork-eval-browser-path", in: arguments)
        modelID = Self.value(after: "--cowork-eval-model", in: arguments) ?? Self.exactModelID
        timeoutSeconds = min(
            900,
            max(1, Int(Self.value(after: "--cowork-eval-timeout-seconds", in: arguments) ?? "240") ?? 240)
        )
    }

    @MainActor
    func makeController(environment: [String: String] = ProcessInfo.processInfo.environment) -> QuillCodeDesktopController {
        let home = URL(fileURLWithPath: homePath, isDirectory: true)
        let workspace = URL(fileURLWithPath: workspacePath, isDirectory: true)
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let paths = QuillCodePaths(home: home)
        let runtimeFactory = QuillCodeRuntimeFactory(paths: paths, environment: environment)
        return QuillCodeDesktopController(
            bootstrap: QuillCodeWorkspaceBootstrap(paths: paths, runtimeFactory: runtimeFactory),
            browserLiveDOMCapturer: nil,
            automationNotifier: QuillCodeDesktopCoworkEvalNotifier(),
            workspaceRoot: workspace
        )
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else { return nil }
        return arguments[valueIndex]
    }
}

struct QuillCodeDesktopCoworkEvalNotifier: QuillCodeAutomationNotifying {
    func deliver(_ report: AutomationRunReport) {}
}

struct QuillCodeDesktopCoworkEvalReport: Encodable {
    struct Tool: Encodable {
        var name: String
        var status: String
        var inputJSON: String?
        var outputJSON: String?
    }

    var ok: Bool
    var timedOut: Bool
    var requestedModelID: String
    var selectedModelID: String
    var prompt: String
    var finalAnswer: String
    var lastError: String?
    var browserURL: String?
    var workspacePath: String
    var durationMilliseconds: Int
    var usage: ModelTokenUsage
    var messageCount: Int
    var timelineItemCount: Int
    var failedToolCount: Int
    var unrecoveredToolFailureCount: Int
    var tools: [Tool]

    static func unrecoveredFailureCount(in tools: [Tool]) -> Int {
        var laterSuccessfulToolNames = Set<String>()
        var count = 0

        for tool in tools.reversed() {
            if tool.status == "done" {
                laterSuccessfulToolNames.insert(tool.name)
            } else if tool.status == "failed", !laterSuccessfulToolNames.contains(tool.name) {
                count += 1
            }
        }
        return count
    }

    func prettyJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}
