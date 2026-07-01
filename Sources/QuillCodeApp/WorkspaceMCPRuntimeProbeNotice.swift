import QuillCodeTools

extension WorkspaceMCPRuntime {
    static func probeNoticeSuffix(for result: MCPServerProbeResult) -> String {
        let parts = [
            probeToolNotice(for: result),
            countedNotice(count: result.resourceNames.count, noun: "resource"),
            countedNotice(count: result.promptNames.count, noun: "prompt")
        ].compactMap { $0 }
        return " (\(parts.joined(separator: "; ")))"
    }

    private static func probeToolNotice(for result: MCPServerProbeResult) -> String {
        let preview = result.toolNames.prefix(3).joined(separator: ", ")
        guard !result.toolNames.isEmpty else { return "0 tools" }

        let remaining = result.toolNames.count - min(result.toolNames.count, 3)
        let noun = result.toolNames.count == 1 ? "tool" : "tools"
        if remaining > 0 {
            return "\(result.toolNames.count) \(noun): \(preview), +\(remaining) more"
        }
        return "\(result.toolNames.count) \(noun): \(preview)"
    }

    private static func countedNotice(count: Int, noun: String) -> String? {
        guard count > 0 else { return nil }
        let suffix = count == 1 ? "" : "s"
        return "\(count) \(noun)\(suffix)"
    }
}
