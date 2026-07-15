import Foundation
import QuillCodeCore

enum WorkspaceCodeReviewSubmitTool {
    static let name = "host.review.submit"

    static let definition = ToolDefinition(
        name: name,
        description: "Submit the complete prioritized review exactly once, including when there are no findings.",
        parametersJSON: schema,
        risk: .read
    )

    static func decode(_ call: ToolCall) throws -> WorkspaceCodeReviewReport {
        guard call.name == name else {
            throw WorkspaceCodeReviewReportError.wrongTool(call.name)
        }
        guard let data = call.argumentsJSON.data(using: .utf8) else {
            throw WorkspaceCodeReviewReportError.invalidJSON
        }

        try validateObjectKeys(in: data)
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw WorkspaceCodeReviewReportError.invalidPayload(String(describing: error))
        }

        let summary = payload.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else {
            throw WorkspaceCodeReviewReportError.emptySummary
        }
        guard payload.findings.count <= WorkspaceCodeReviewReport.maximumFindingCount else {
            throw WorkspaceCodeReviewReportError.tooManyFindings
        }

        var seen = Set<FindingIdentity>()
        var findings: [WorkspaceCodeReviewFinding] = []
        for raw in payload.findings {
            let finding = try normalizedFinding(raw)
            guard seen.insert(FindingIdentity(finding: finding)).inserted else { continue }
            findings.append(finding)
        }
        findings.sort(by: findingSort)
        return WorkspaceCodeReviewReport(summary: summary, findings: findings)
    }

    private static let schema = #"""
    {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "summary": {
          "type": "string",
          "description": "Concise overall review assessment."
        },
        "findings": {
          "type": "array",
          "maxItems": 100,
          "items": {
            "type": "object",
            "additionalProperties": false,
            "properties": {
              "priority": { "type": "string", "enum": ["P0", "P1", "P2", "P3"] },
              "title": { "type": "string" },
              "body": { "type": "string" },
              "path": {
                "type": "string",
                "description": "Workspace-relative file path."
              },
              "line": { "type": "integer", "minimum": 1 },
              "endLine": { "type": "integer", "minimum": 1 }
            },
            "required": ["priority", "title", "body", "path"]
          }
        }
      },
      "required": ["summary", "findings"]
    }
    """#

    private static func normalizedFinding(_ raw: Payload.Finding) throws -> WorkspaceCodeReviewFinding {
        guard let priority = WorkspaceCodeReviewPriority(rawValue: raw.priority.uppercased()) else {
            throw WorkspaceCodeReviewReportError.invalidPriority(raw.priority)
        }
        let title = raw.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = raw.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw WorkspaceCodeReviewReportError.emptyTitle }
        guard !body.isEmpty else { throw WorkspaceCodeReviewReportError.emptyBody }
        guard let path = normalizedPath(raw.path) else {
            throw WorkspaceCodeReviewReportError.invalidPath(raw.path)
        }
        guard raw.line.map({ $0 > 0 }) ?? true else {
            throw WorkspaceCodeReviewReportError.invalidLine
        }
        guard raw.endLine.map({ $0 > 0 }) ?? true else {
            throw WorkspaceCodeReviewReportError.invalidLine
        }
        guard raw.endLine == nil || raw.line != nil else { throw WorkspaceCodeReviewReportError.invalidLine }

        let line = raw.line.map { min($0, raw.endLine ?? $0) }
        let endLine = raw.line.flatMap { start in raw.endLine.map { max(start, $0) } }
        return WorkspaceCodeReviewFinding(
            priority: priority,
            title: title,
            body: body,
            path: path,
            line: line,
            endLine: endLine
        )
    }

    private static func normalizedPath(_ rawPath: String) -> String? {
        var path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        while path.hasPrefix("./") { path.removeFirst(2) }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty,
              path != ".",
              !path.hasPrefix("/"),
              !path.hasPrefix("~"),
              !path.contains("\\"),
              !path.contains("\0"),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else {
            return nil
        }
        return path
    }

    private static func validateObjectKeys(in data: Data) throws {
        let raw: Any
        do {
            raw = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw WorkspaceCodeReviewReportError.invalidJSON
        }
        guard let payload = raw as? [String: Any] else {
            throw WorkspaceCodeReviewReportError.invalidPayload("top-level value must be an object")
        }
        try validateKeys(
            Set(payload.keys),
            expected: ["summary", "findings"],
            context: "top-level"
        )
        guard let rawFindings = payload["findings"] as? [Any] else { return }
        let expectedFindingKeys: Set<String> = ["priority", "title", "body", "path", "line", "endLine"]
        for (index, rawFinding) in rawFindings.enumerated() {
            guard let finding = rawFinding as? [String: Any] else { continue }
            try validateKeys(Set(finding.keys), expected: expectedFindingKeys, context: "finding \(index)")
        }
    }

    private static func validateKeys(
        _ actual: Set<String>,
        expected: Set<String>,
        context: String
    ) throws {
        let unknown = actual.subtracting(expected).sorted()
        guard unknown.isEmpty else {
            throw WorkspaceCodeReviewReportError.invalidPayload(
                "\(context) has unknown field(s): \(unknown.joined(separator: ", "))"
            )
        }
    }

    private static func findingSort(_ lhs: WorkspaceCodeReviewFinding, _ rhs: WorkspaceCodeReviewFinding) -> Bool {
        if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
        if lhs.path != rhs.path { return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending }
        if lhs.line != rhs.line { return (lhs.line ?? 0) < (rhs.line ?? 0) }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    private struct Payload: Decodable {
        var summary: String
        var findings: [Finding]

        struct Finding: Decodable {
            var priority: String
            var title: String
            var body: String
            var path: String
            var line: Int?
            var endLine: Int?
        }
    }

    private struct FindingIdentity: Hashable {
        var priority: WorkspaceCodeReviewPriority
        var title: String
        var path: String
        var line: Int?

        init(finding: WorkspaceCodeReviewFinding) {
            priority = finding.priority
            title = finding.title.lowercased()
            path = finding.path
            line = finding.line
        }
    }
}

enum WorkspaceCodeReviewReportError: Error, Equatable, CustomStringConvertible {
    case wrongTool(String)
    case invalidJSON
    case invalidPayload(String)
    case emptySummary
    case tooManyFindings
    case invalidPriority(String)
    case emptyTitle
    case emptyBody
    case invalidPath(String)
    case invalidLine

    var description: String {
        switch self {
        case .wrongTool(let name): "Expected \(WorkspaceCodeReviewSubmitTool.name), received \(name)."
        case .invalidJSON: "The review report was not valid UTF-8 JSON."
        case .invalidPayload(let detail): "The review report did not match the required schema: \(detail)"
        case .emptySummary: "The review summary cannot be empty."
        case .tooManyFindings:
            "A review report can contain at most \(WorkspaceCodeReviewReport.maximumFindingCount) findings."
        case .invalidPriority(let priority): "Unknown review priority: \(priority)."
        case .emptyTitle: "Every review finding needs a title."
        case .emptyBody: "Every review finding needs an explanation."
        case .invalidPath(let path): "Review finding paths must be workspace-relative: \(path)."
        case .invalidLine: "Review finding line numbers must be positive and endLine requires line."
        }
    }
}

actor WorkspaceCodeReviewReportCollector {
    private(set) var report: WorkspaceCodeReviewReport?

    func capture(_ call: ToolCall) -> ToolResult? {
        guard call.name == WorkspaceCodeReviewSubmitTool.name else { return nil }
        guard report == nil else {
            return ToolResult(ok: false, error: "The complete code-review report was already submitted.")
        }
        do {
            let decoded = try WorkspaceCodeReviewSubmitTool.decode(call)
            report = decoded
            return ToolResult(
                ok: true,
                stdout: #"{"accepted":true,"findingCount":\#(decoded.findings.count)}"#
            )
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }
}
