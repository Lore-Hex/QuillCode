import Foundation
import QuillCodeCore

/// Requires a deterministic audit when the request gives a mechanically testable artifact
/// contract. Readback proves only that bytes were saved; it cannot prove row counts, cell order,
/// numeric representation, or chart geometry. A successful validator is tied to the latest write,
/// so any subsequent rewrite re-arms the gate.
enum AgentArtifactContractAuditGate {
    struct Correction: Equatable {
        var path: String
        var prompt: String
    }

    static let correctionLimitPerPath = 3

    static func requiresAudit(in userMessage: String) -> Bool {
        let patterns = [
            #"(?is)\bexactly\s+(?:\d+|one|two|three|four|five|six|seven|eight|nine|ten)\s+(?:[\w-]+\s+){0,3}(?:rows?|records?|entries|items|sections?|emails?|slides?|sheets?|columns?|cells?|series)\b"#,
            #"(?is)\bfirst\s+(?:\d+|one|two|three|four|five|six|seven|eight|nine|ten)\s+(?:cells?|columns?|rows?|fields?)\b"#,
            #"(?is)\b(?:same|single)\s+<(?:tr|td|th)\b"#,
            #"(?is)\b(?:each|every)\s+(?:[\w-]+\s+){0,3}(?:row|record|entry|item|section|email|slide|sheet|column|cell|series)\b.{0,120}\b(?:must|needs?\s+to|has\s+to|include|contain)\b"#,
            #"(?is)\b(?:restate|convert|calculate|compute|reconcile|transform)\s+(?:each|every)\s+(?:[\w-]+\s+){0,4}(?:rows?|records?|entries?|items?)\b"#,
            #"(?is)\b(?:deterministic|programmatic|machine[- ]checkable)\s+(?:post[- ]write\s+)?(?:validator|validation|audit)\b"#,
        ]
        let range = NSRange(userMessage.startIndex..., in: userMessage)
        return patterns.contains { pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
            return regex.firstMatch(in: userMessage, range: range) != nil
        }
    }

    static func auditedPaths(
        for call: ToolCall,
        among requiredPaths: Set<String>
    ) -> Set<String> {
        guard call.name == ToolDefinition.shellRun.name,
              let arguments = try? ToolArguments(call.argumentsJSON),
              let command = arguments.string("cmd"),
              isValidatorCommand(command)
        else { return [] }

        let normalizedCommand = command.replacingOccurrences(of: "\\", with: "/").casefolded
        return Set(requiredPaths.filter { path in
            normalizedCommand.contains(
                AgentArtifactVerificationGate.normalizedPath(path).casefolded
            )
        })
    }

    static func correction(
        path: String,
        tools: [ToolDefinition],
        correctionCount: Int
    ) -> Correction? {
        guard correctionCount < correctionLimitPerPath,
              tools.contains(where: { $0.name == ToolDefinition.shellRun.name }) else {
            return nil
        }
        let normalized = AgentArtifactVerificationGate.normalizedPath(path)
        return Correction(
            path: normalized,
            prompt: """
            Artifact contract audit required for ./\(normalized). Readback alone is not validation. \
            Run one deterministic validator with host.shell.run against the saved artifact. Parse \
            the artifact using an appropriate structured parser and assert every explicit, \
            mechanically testable requirement in the original request: counts, row/cell/field \
            order, required raw value formats, labels, and chart-series data. For SVG or canvas \
            coordinates, also assert that value changes map in the correct visual direction. The \
            command must contain real assertions or validation checks, print a concise PASS summary, \
            and exit nonzero with named failures. A presence-only grep or another readback is not \
            sufficient. If it fails, rewrite the complete artifact and rerun the validator; do not \
            claim completion until the latest write passes.
            """
        )
    }

    static func exhaustionReason(path: String) -> String {
        let normalized = AgentArtifactVerificationGate.normalizedPath(path)
        return "Stopped because ./\(normalized) still lacked a successful deterministic "
            + "contract audit after \(correctionLimitPerPath) corrective attempts."
    }

    private static func isValidatorCommand(_ command: String) -> Bool {
        let executorPattern = #"(?is)\b(?:python\d*|ruby|perl|node|deno|awk|jq|xmllint|tidy)\b"#
        let assertionPattern = #"(?is)(?:\b(?:assert|validate|validator|verify|verification|lint|check)\b|\b(?:xmllint|tidy)\b|raise\s+SystemExit|exit\s*\()"#
        let range = NSRange(command.startIndex..., in: command)
        guard let executorRegex = try? NSRegularExpression(pattern: executorPattern),
              let assertionRegex = try? NSRegularExpression(pattern: assertionPattern)
        else { return false }
        return executorRegex.firstMatch(in: command, range: range) != nil
            && assertionRegex.firstMatch(in: command, range: range) != nil
    }
}

private extension String {
    var casefolded: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
