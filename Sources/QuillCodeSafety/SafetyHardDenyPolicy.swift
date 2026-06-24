import Foundation

struct SafetyHardDenyPolicy: Sendable {
    private static let blockedCommandFragments = [
        "rm -rf /",
        "mkfs",
        "dd if=",
        "security find-generic-password",
        "cat ~/.ssh",
        "aws_secret_access_key",
        "chmod -r 777 /",
        ":(){"
    ]

    func reason(for context: SafetyContext) -> String? {
        let haystack = normalizedToolText(context)
        if blocksRemoteShellPipe(haystack) {
            return "Auto mode blocks piping remote downloads into a shell."
        }
        if let match = Self.blockedCommandFragments.first(where: { haystack.contains($0) }) {
            return "Auto mode blocks high-risk command pattern: \(match)."
        }
        return nil
    }

    private func normalizedToolText(_ context: SafetyContext) -> String {
        "\(context.toolCall.name) \(context.toolCall.argumentsJSON)"
            .lowercased()
            .replacingOccurrences(of: "\\/", with: "/")
    }

    private func blocksRemoteShellPipe(_ haystack: String) -> Bool {
        haystack.contains("curl ") && (haystack.contains("| sh") || haystack.contains("| bash"))
    }
}
