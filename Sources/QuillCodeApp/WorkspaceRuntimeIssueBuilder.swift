import Foundation
import QuillCodeCore

struct WorkspaceRuntimeIssueBuilder: Sendable, Hashable {
    var config: AppConfig
    var hasStoredAPIKey: Bool
    var modelID: String
    var agentStatus: String
    var lastError: String?

    init(
        config: AppConfig,
        hasStoredAPIKey: Bool,
        modelID: String,
        agentStatus: String,
        lastError: String? = nil
    ) {
        self.config = config
        self.hasStoredAPIKey = hasStoredAPIKey
        self.modelID = modelID
        self.agentStatus = agentStatus
        self.lastError = lastError
    }

    func surface() -> RuntimeIssueSurface? {
        if let lastError,
           let issue = Self.issue(from: lastError, config: config) {
            return issue.withDiagnostics(diagnostics(lastError: lastError))
        }

        switch agentStatus {
        case QuillCodeRuntimeStatusLabel.signInWithTrustedRouter:
            return RuntimeIssueSurface(
                severity: .warning,
                title: "TrustedRouter sign-in needed",
                message: "Sign in with TrustedRouter to use live models. Mock mode stays available for deterministic local testing.",
                actionLabel: "Open Settings",
                diagnostics: diagnostics()
            )
        case QuillCodeRuntimeStatusLabel.developerKeyNeeded:
            return RuntimeIssueSurface(
                severity: .warning,
                title: "Developer key needed",
                message: "Developer override is enabled, but no TrustedRouter API key is saved.",
                actionLabel: "Add key",
                diagnostics: diagnostics()
            )
        default:
            return nil
        }
    }

    func diagnostics(lastError: String? = nil) -> [RuntimeDiagnosticSurface] {
        var diagnostics = [
            RuntimeDiagnosticSurface(label: "API base URL", value: config.apiBaseURL),
            RuntimeDiagnosticSurface(label: "Authentication", value: Self.authModeLabel(config.authMode)),
            RuntimeDiagnosticSurface(label: "Key state", value: hasStoredAPIKey ? "Configured" : "Missing"),
            RuntimeDiagnosticSurface(label: "Model", value: modelID),
            RuntimeDiagnosticSurface(label: "Agent status", value: agentStatus)
        ]
        if let lastError {
            diagnostics.append(contentsOf: Self.rateLimitDiagnostics(from: lastError))
            diagnostics.append(RuntimeDiagnosticSurface(label: "Last error", value: Self.redactedDiagnosticError(lastError)))
        }
        return diagnostics
    }

    static func issue(from error: String, config: AppConfig) -> RuntimeIssueSurface? {
        let trimmed = error.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.lowercased()

        if normalized.contains("api key is not configured") {
            return RuntimeIssueSurface(
                severity: .warning,
                title: "TrustedRouter sign-in needed",
                message: "Sign in with TrustedRouter or switch to developer override with a valid key.",
                actionLabel: "Open Settings"
            )
        }
        if normalized.contains("401") || normalized.contains("invalid api key") || normalized.contains("unauthorized") {
            return RuntimeIssueSurface(
                severity: .error,
                title: "TrustedRouter key rejected",
                message: "The saved key was rejected by \(config.apiBaseURL). Sign in again or replace the developer key.",
                actionLabel: "Fix key"
            )
        }
        if isRateLimitError(normalized) {
            return RuntimeIssueSurface(
                severity: .warning,
                title: "TrustedRouter rate limit reached",
                message: "TrustedRouter or the selected provider is rate limiting this request. Wait for reset, retry later, or switch models.",
                actionLabel: "Switch model"
            )
        }
        if normalized.contains("timed out") ||
            normalized.contains("not connected") ||
            normalized.contains("network is unreachable") ||
            normalized.contains("cannot connect") ||
            normalized.contains("could not connect") ||
            normalized.contains("cannot find host") {
            return RuntimeIssueSurface(
                severity: .error,
                title: "TrustedRouter network issue",
                message: "QuillCode could not reach \(config.apiBaseURL). Check the network or API base URL, then retry.",
                actionLabel: "Retry"
            )
        }
        if normalized.contains("empty response") {
            return RuntimeIssueSurface(
                severity: .warning,
                title: "TrustedRouter returned no content",
                message: "Retry the turn or switch models. If it repeats, check provider status.",
                actionLabel: "Retry"
            )
        }
        if normalized.contains("valid quillcode action json") || normalized.contains("empty argument object") {
            return RuntimeIssueSurface(
                severity: .warning,
                title: "Model response was malformed",
                message: "The selected model did not follow QuillCode's action schema. Try \(TrustedRouterDefaults.fastModelDisplayName), \(TrustedRouterDefaults.fusionModelDisplayName), or another coding model.",
                actionLabel: "Switch model"
            )
        }
        return RuntimeIssueSurface(
            severity: .error,
            title: "Run failed",
            message: String(trimmed.prefix(260)),
            actionLabel: "Retry"
        )
    }

    static func rateLimitDiagnostics(from error: String) -> [RuntimeDiagnosticSurface] {
        let normalized = error.lowercased()
        guard isRateLimitError(normalized) else { return [] }
        var diagnostics = [
            RuntimeDiagnosticSurface(label: "Provider status", value: "Rate limited")
        ]
        if let retryAfter = firstCapture(
            in: error,
            pattern: #"(?i)\bretry[- ]after\b\s*[:=]?\s*([0-9]+)\s*(?:s|sec|secs|second|seconds)?"#
        ) {
            diagnostics.append(RuntimeDiagnosticSurface(label: "Retry after", value: "\(retryAfter)s"))
        }
        if let remaining = firstCapture(
            in: error,
            pattern: #"(?i)\bx[-_]?ratelimit[-_]?remaining\b\s*[:=]?\s*([0-9]+)"#
        ) {
            diagnostics.append(RuntimeDiagnosticSurface(label: "Rate limit remaining", value: remaining))
        }
        return diagnostics
    }

    static func redactedDiagnosticError(_ error: String) -> String {
        let redacted = error
            .replacingOccurrences(
                of: #"sk-[A-Za-z0-9_-]{8,}"#,
                with: "sk-...redacted",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"Bearer\s+[A-Za-z0-9._-]{12,}"#,
                with: "Bearer ...redacted",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(redacted.prefix(260))
    }

    private static func authModeLabel(_ authMode: TrustedRouterAuthMode) -> String {
        switch authMode {
        case .oauth:
            return "TrustedRouter login"
        case .developerOverride:
            return "Developer override"
        }
    }

    private static func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return String(text[captureRange])
    }

    private static func isRateLimitError(_ normalizedError: String) -> Bool {
        normalizedError.contains("429") ||
            normalizedError.contains("rate limit") ||
            normalizedError.contains("ratelimit") ||
            normalizedError.contains("quota exceeded") ||
            normalizedError.contains("usage limit") ||
            normalizedError.contains("too many requests")
    }
}
