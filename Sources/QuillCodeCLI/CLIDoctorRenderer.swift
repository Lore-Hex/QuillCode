import CQuillPTY
import Foundation

enum CLIDoctorRenderer {
    static func json(_ report: CLIDoctorReport) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(report), as: UTF8.self) + "\n"
    }

    static func human(
        _ report: CLIDoctorReport,
        request: CLIDoctorRequest,
        environment: [String: String]
    ) -> String {
        let color = !request.disablesColor
            && environment["NO_COLOR"] == nil
            && cquill_fd_isatty(Int32(FileHandle.standardOutput.fileDescriptor)) == 1
        let headingSeparator = request.usesASCII ? "|" : "·"
        var lines = [
            "QuillCode Doctor v\(report.quillCodeVersion) \(headingSeparator) \(platform(in: report))",
            ""
        ]

        let notes = report.orderedChecks.filter { $0.status != .ok }
        if !notes.isEmpty {
            lines.append("Notes")
            for check in notes {
                lines.append(row(check, request: request, color: color))
                if let remediation = check.remediation {
                    lines.append("      \(CLIDoctorSanitizer.singleLine(remediation))")
                }
            }
            lines.append(separator(ascii: request.usesASCII))
            lines.append("")
        }

        for section in sections(report.orderedChecks) {
            lines.append(section.title)
            for check in section.checks {
                lines.append(row(check, request: request, color: color))
                guard !request.summaryOnly else { continue }
                appendDetails(
                    check.details,
                    expandsLongLists: request.expandsLongLists,
                    to: &lines
                )
                for issue in check.issues {
                    lines.append("      issue: \(CLIDoctorSanitizer.singleLine(issue.cause))")
                }
                if let remediation = check.remediation {
                    lines.append("      fix: \(CLIDoctorSanitizer.singleLine(remediation))")
                }
            }
            lines.append("")
        }

        lines.append(separator(ascii: request.usesASCII))
        let counts = Dictionary(grouping: report.checks.values, by: \.status).mapValues(\.count)
        let suffix = report.overallStatus == .fail ? "failed" : "healthy"
        let summarySeparator = request.usesASCII ? "-" : "—"
        lines.append(
            "\(counts[.ok, default: 0]) ok | "
                + "\(counts[.warning, default: 0]) warn | "
                + "\(counts[.fail, default: 0]) fail \(summarySeparator) \(suffix)"
        )
        if request.summaryOnly {
            lines.append("")
            lines.append("Run `quill-code doctor` without --summary for detailed diagnostics.")
        }
        if !request.expandsLongLists {
            let optionSeparator = request.usesASCII ? "|" : "·"
            lines.append("`--all` expands truncated lists \(optionSeparator) `--json` emits a redacted report")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static let help = """
    Diagnose local QuillCode installation, config, auth, and runtime health

    Usage: quill-code [--home PATH] doctor [OPTIONS]

    Options:
      --json       Emit a redacted machine-readable report
      --summary    Only show grouped check rows and the final count summary
      --all        Expand long lists in detailed human output
      --no-color   Disable ANSI color in human output
      --ascii      Use ASCII status labels and separators in human output
      -h, --help   Show this help
    """

    private static func row(
        _ check: CLIDoctorCheck,
        request: CLIDoctorRequest,
        color: Bool
    ) -> String {
        let token: String
        switch (check.status, request.usesASCII) {
        case (.ok, true): token = "[ok]"
        case (.warning, true): token = "[!!]"
        case (.fail, true): token = "[XX]"
        case (.ok, false): token = "[✓]"
        case (.warning, false): token = "[!]"
        case (.fail, false): token = "[✕]"
        }
        let coloredToken: String
        if color {
            let code = switch check.status {
            case .ok: "32"
            case .warning: "33"
            case .fail: "31"
            }
            coloredToken = "\u{001B}[\(code)m\(token)\u{001B}[0m"
        } else {
            coloredToken = token
        }
        return "  \(coloredToken) \(padded(check.category, width: 12)) \(CLIDoctorSanitizer.singleLine(check.summary))"
    }

    private static func appendDetails(
        _ details: [String: CLIDoctorDetail],
        expandsLongLists: Bool,
        to lines: inout [String]
    ) {
        for key in details.keys.sorted() {
            guard let detail = details[key] else { continue }
            let safeKey = CLIDoctorSanitizer.singleLine(key, limit: 80)
            switch detail {
            case .text(let value):
                lines.append("      \(safeKey): \(CLIDoctorSanitizer.singleLine(value))")
            case .list(let values):
                let limit = expandsLongLists ? values.count : min(5, values.count)
                if values.isEmpty {
                    lines.append("      \(safeKey): none")
                } else {
                    lines.append("      \(safeKey):")
                    for value in values.prefix(limit) {
                        lines.append("        - \(CLIDoctorSanitizer.singleLine(value))")
                    }
                    if limit < values.count {
                        let marker = expandsLongLists ? "" : "... "
                        lines.append("        - \(marker)\(values.count - limit) more")
                    }
                }
            }
        }
    }

    private static func platform(in report: CLIDoctorReport) -> String {
        guard case .text(let platform) = report.checks["runtime.provenance"]?.details["platform"] else {
            return "unknown platform"
        }
        return CLIDoctorSanitizer.singleLine(platform, limit: 80)
    }

    private static func sections(_ checks: [CLIDoctorCheck]) -> [(title: String, checks: [CLIDoctorCheck])] {
        let definitions: [(String, Set<String>)] = [
            ("Environment", ["system", "runtime", "install", "search", "git", "terminal"]),
            ("Configuration", ["config", "auth", "mcp", "sandbox"]),
            ("State", ["state", "threads"]),
            ("Connectivity", ["network", "reachability"]),
            ("Background Server", ["app-server"])
        ]
        return definitions.compactMap { title, categories in
            let matching = checks.filter { categories.contains($0.category) }
            return matching.isEmpty ? nil : (title, matching)
        }
    }

    private static func separator(ascii: Bool) -> String {
        String(repeating: ascii ? "-" : "─", count: 61)
    }

    private static func padded(_ value: String, width: Int) -> String {
        let value = CLIDoctorSanitizer.singleLine(value, limit: width)
        return value + String(repeating: " ", count: max(0, width - value.count))
    }
}
