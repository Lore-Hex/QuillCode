import Foundation
import QuillCodeAgent
import QuillCodeApp
import QuillCodeCore
import QuillCodePersistence

struct QuillCodeDesktopCoworkEvalRequest: Sendable {
    static let defaultModelID = "deepseek/deepseek-v4-flash-0731"
    static let maximumTimeoutSeconds = 21_600
    static let maximumToolSteps = 4_096

    var homePath: String
    var workspacePath: String
    var promptPath: String
    var reportPath: String?
    var screenshotPath: String?
    var browserPath: String?
    var modelID: String
    var isConfidential: Bool
    var timeoutSeconds: Int
    var maxToolSteps: Int
    var runSpendFuseUSD: Double?

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
        screenshotPath = Self.value(after: "--cowork-eval-screenshot", in: arguments)
        browserPath = Self.value(after: "--cowork-eval-browser-path", in: arguments)
        isConfidential = arguments.contains("--cowork-eval-confidential")
        modelID = isConfidential
            ? TrustedRouterDefaults.e2eModel
            : TrustedRouterDefaults.normalizedDefaultModelID(
                Self.value(after: "--cowork-eval-model", in: arguments) ?? Self.defaultModelID
            )
        timeoutSeconds = min(
            Self.maximumTimeoutSeconds,
            max(1, Int(Self.value(after: "--cowork-eval-timeout-seconds", in: arguments) ?? "240") ?? 240)
        )
        maxToolSteps = min(
            Self.maximumToolSteps,
            max(
                1,
                Int(Self.value(after: "--cowork-eval-max-tool-steps", in: arguments)
                    ?? "\(AppConfig.defaultMaxToolSteps)") ?? AppConfig.defaultMaxToolSteps
            )
        )
        runSpendFuseUSD = Self.spendFuse(
            from: Self.value(after: "--cowork-eval-run-spend-fuse-usd", in: arguments)
        )
    }

    @MainActor
    func makeController(environment: [String: String] = ProcessInfo.processInfo.environment) -> QuillCodeDesktopController {
        let home = URL(fileURLWithPath: homePath, isDirectory: true)
        let workspace = URL(fileURLWithPath: workspacePath, isDirectory: true)
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let paths = QuillCodePaths(home: home)
        var config = (try? ConfigStore(fileURL: paths.configFile).load()) ?? AppConfig()
        config.defaultModel = modelID
        config.maxToolSteps = maxToolSteps
        config.runSpendFuseUSD = runSpendFuseUSD
        try? ConfigStore(fileURL: paths.configFile).save(config)
        let runtimeFactory = QuillCodeRuntimeFactory(paths: paths, environment: environment)
        return QuillCodeDesktopController(
            bootstrap: QuillCodeWorkspaceBootstrap(paths: paths, runtimeFactory: runtimeFactory),
            browserLiveDOMCapturer: nil,
            automationNotifier: QuillCodeDesktopCoworkEvalNotifier(),
            updateController: QuillCodeDesktopUpdateController(
                configuration: nil,
                installResultURL: nil
            ),
            workspaceRoot: workspace
        )
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else { return nil }
        return arguments[valueIndex]
    }

    private static func spendFuse(from rawValue: String?) -> Double? {
        guard let rawValue else { return 1.0 }
        if ["none", "off", "disabled"].contains(rawValue.lowercased()) {
            return nil
        }
        guard let value = Double(rawValue), value.isFinite, value > 0 else { return 1.0 }
        return value
    }
}

struct QuillCodeDesktopCoworkEvalNotifier: QuillCodeAutomationNotifying {
    func deliver(_ report: AutomationRunReport) {}
}

struct QuillCodeDesktopCoworkEvalReport: Encodable {
    struct ScheduledAutomation: Encodable {
        struct Recurrence: Encodable {
            var interval: Int
            var unit: String
            var weekdays: [Int]?
            var hour: Int?
            var minute: Int?
        }

        var id: String
        var title: String
        var detail: String
        var kind: String
        var status: String
        var scheduleKind: String
        var scheduleDescription: String
        var nextRunAt: Date?
        var recurrence: Recurrence?

        init(_ automation: QuillAutomation) {
            id = automation.id.uuidString
            title = automation.title
            detail = automation.detail
            kind = automation.kind.rawValue
            status = automation.status.rawValue
            scheduleKind = automation.scheduleKind.rawValue
            scheduleDescription = automation.scheduleDescription
            nextRunAt = automation.nextRunAt
            recurrence = automation.recurrence.map {
                Recurrence(
                    interval: $0.interval,
                    unit: $0.unit.rawValue,
                    weekdays: $0.weekdays,
                    hour: $0.hour,
                    minute: $0.minute
                )
            }
        }
    }

    struct Screenshot: Encodable {
        var path: String
        var width: Int
        var height: Int
        var opaquePixelRatio: Double
        var brightPixelRatio: Double
        var accentPixelRatio: Double
        var distinctColorBuckets: Int
    }

    struct Tool: Encodable {
        var name: String
        var status: String
        var inputJSON: String?
        var outputJSON: String?
    }

    var ok: Bool
    var timedOut: Bool
    var stopReason: String?
    var stopReasonDetail: String?
    var requestedModelID: String
    var selectedModelID: String
    var isConfidential: Bool
    var prompt: String
    var finalAnswer: String
    var lastError: String?
    var browserURL: String?
    var workspacePath: String
    var windowSource: String
    var workspaceWindowCount: Int
    var screenshot: Screenshot?
    var desktopCaptureError: String?
    var scheduledAutomation: ScheduledAutomation?
    var durationMilliseconds: Int
    var usage: ModelTokenUsage
    var messageCount: Int
    var timelineItemCount: Int
    var failedToolCount: Int
    var unrecoveredToolFailureCount: Int
    var tools: [Tool]

    static func stopReasonFields(_ reason: AgentRunStopReason?) -> (name: String?, detail: String?) {
        switch reason {
        case .finished:
            return ("finished", nil)
        case .toolStepCeilingExhausted(let limit):
            return ("tool-step-ceiling-exhausted", "Reached the \(limit)-step tool ceiling.")
        case .flailDetected(let reason):
            return ("flail-detected", reason)
        case .spendFuseApprovalRequired(let totalUSD, let fuseUSD):
            return (
                "spend-fuse-approval-required",
                String(format: "Spent $%.4f against the $%.4f run fuse.", totalUSD, fuseUSD)
            )
        case .approvalRequired(let requestID):
            return ("approval-required", "Approval request \(requestID) is pending.")
        case .autoReviewCircuitBreaker(let reason):
            return ("auto-review-circuit-breaker", reason)
        case nil:
            return (nil, nil)
        }
    }

    static func unrecoveredFailureCount(in tools: [Tool]) -> Int {
        var hasLaterSuccess = false
        var count = 0

        for tool in tools.reversed() {
            if tool.status == "done" {
                hasLaterSuccess = true
            } else if tool.status == "failed", !hasLaterSuccess {
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
