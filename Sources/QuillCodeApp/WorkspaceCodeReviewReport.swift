public struct WorkspaceCodeReviewReport: Codable, Sendable, Hashable {
    public static let maximumFindingCount = 100

    public var summary: String
    public var findings: [WorkspaceCodeReviewFinding]

    public init(summary: String, findings: [WorkspaceCodeReviewFinding]) {
        self.summary = summary
        self.findings = findings
    }

    public var transcriptMarkdown: String {
        var lines = ["## Code review", "", summary]
        guard !findings.isEmpty else {
            lines.append(contentsOf: ["", "No actionable findings."])
            return lines.joined(separator: "\n")
        }

        lines.append("")
        lines.append(contentsOf: findings.map(Self.markdownLine))
        return lines.joined(separator: "\n")
    }

    private static func markdownLine(for finding: WorkspaceCodeReviewFinding) -> String {
        let location = finding.line.map { line in
            let endLine = finding.endLine ?? line
            return endLine == line
                ? "`\(finding.path):\(line)`"
                : "`\(finding.path):\(line)-\(endLine)`"
        } ?? "`\(finding.path)`"

        return "- **[\(finding.priority.label)] \(finding.title)** \(location) — \(finding.body)"
    }
}
