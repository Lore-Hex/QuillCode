import Foundation

/// The branch and upstream-tracking state parsed from the leading `## ` header of
/// `git status --short --branch` output. Used to surface a worktree/project's branch
/// and how far it is ahead/behind its upstream without any extra git invocation.
public struct GitBranchStatus: Codable, Sendable, Hashable {
    public var branch: String
    public var upstream: String?
    public var ahead: Int
    public var behind: Int
    public var isDetached: Bool

    public init(branch: String, upstream: String? = nil, ahead: Int = 0, behind: Int = 0, isDetached: Bool = false) {
        self.branch = branch
        self.upstream = upstream
        self.ahead = ahead
        self.behind = behind
        self.isDetached = isDetached
    }

    /// A compact one-line label, e.g. `feature/x ↑2 ↓1`, `main`, or `(detached)`.
    /// Arrows are omitted when the count is zero. This is the single shared place
    /// label formatting lives, so renderers only display the resulting string.
    public var compactLabel: String {
        if isDetached { return "(detached)" }
        guard !branch.isEmpty else { return "" }
        var label = branch
        if ahead > 0 { label += " ↑\(ahead)" }
        if behind > 0 { label += " ↓\(behind)" }
        return label
    }

    /// Parses the `## ` branch header from `git status --short --branch` output.
    /// Returns `nil` when there is no parseable header (so the chip degrades away).
    public static func parse(statusShortBranchOutput: String) -> GitBranchStatus? {
        let firstLine = statusShortBranchOutput
            .split(separator: "\n", omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? ""
        guard firstLine.hasPrefix("## ") else { return nil }

        var rest = String(firstLine.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        if rest == "HEAD (no branch)" || rest.hasPrefix("HEAD (no branch)") {
            return GitBranchStatus(branch: "", upstream: nil, ahead: 0, behind: 0, isDetached: true)
        }

        var ahead = 0
        var behind = 0
        if let bracketStart = rest.lastIndex(of: "["), rest.hasSuffix("]") {
            let inside = String(rest[rest.index(after: bracketStart)..<rest.index(before: rest.endIndex)])
            rest = String(rest[rest.startIndex..<bracketStart]).trimmingCharacters(in: .whitespaces)
            for segment in inside.split(separator: ",") {
                let tokens = segment.trimmingCharacters(in: .whitespaces).split(separator: " ")
                guard tokens.count == 2, let count = Int(tokens[1]) else { continue }
                if tokens[0] == "ahead" { ahead = count }
                else if tokens[0] == "behind" { behind = count }
            }
        }

        let branch: String
        let upstream: String?
        if let separator = rest.range(of: "...") {
            branch = String(rest[rest.startIndex..<separator.lowerBound])
            let upstreamValue = String(rest[separator.upperBound...]).trimmingCharacters(in: .whitespaces)
            upstream = upstreamValue.isEmpty ? nil : upstreamValue
        } else {
            branch = rest
            upstream = nil
        }
        guard !branch.isEmpty else { return nil }
        return GitBranchStatus(branch: branch, upstream: upstream, ahead: ahead, behind: behind, isDetached: false)
    }
}
