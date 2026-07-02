import Foundation
import QuillCodeCore

/// Detects an agent run that is BUSY but going NOWHERE — the overnight failure mode the wall-clock
/// watchdog cannot see. A hung run stops calling tools; a flailing run keeps calling them: the same
/// `swift test` six times with the identical failure, an edit/undo ping-pong, the same command with
/// no workspace change. This engine is pure and deterministic: the run loop feeds it one
/// `FlailTurnRecord` per tool turn and gets a verdict back. No clocks, no I/O.
///
/// Escalation contract: a rule firing yields `.suspected` until the wiring layer injects a
/// self-assessment turn (recorded via `recordAssessment()`); if the flail persists after that, the
/// verdict escalates to `.confirmed` — the wiring should then pause the run and notify. Genuine
/// progress (a new, non-empty workspace delta with no rule firing) clears the assessment strike.

// MARK: - Fingerprint

/// A normalized identity for one tool call, so "the same action repeated" survives cosmetic noise:
/// JSON key order, whitespace runs inside string arguments, and absolute-vs-workspace-relative paths.
public struct ToolCallFingerprint: Sendable, Hashable {
    public let value: String

    public static func make(name: String, argumentsJSON: String, workspaceRoot: URL? = nil) -> ToolCallFingerprint {
        ToolCallFingerprint(value: "\(name)|\(canonicalArguments(argumentsJSON, workspaceRoot: workspaceRoot))")
    }

    public static func make(call: ToolCall, workspaceRoot: URL? = nil) -> ToolCallFingerprint {
        make(name: call.name, argumentsJSON: call.argumentsJSON, workspaceRoot: workspaceRoot)
    }

    /// Sorted-keys re-encode with normalized string values; unparseable JSON falls back to
    /// whitespace-collapsed raw text so a malformed call still fingerprints stably.
    private static func canonicalArguments(_ json: String, workspaceRoot: URL?) -> String {
        guard
            let data = json.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let canonical = try? JSONSerialization.data(
                withJSONObject: normalize(object, workspaceRoot: workspaceRoot),
                options: [.sortedKeys]
            )
        else {
            return collapseWhitespace(json)
        }
        return String(decoding: canonical, as: UTF8.self)
    }

    private static func normalize(_ value: Any, workspaceRoot: URL?) -> Any {
        switch value {
        case let string as String:
            var normalized = collapseWhitespace(string)
            if let root = workspaceRoot?.standardizedFileURL.path {
                let prefix = root.hasSuffix("/") ? root : root + "/"
                normalized = normalized.replacingOccurrences(of: prefix, with: "")
            }
            return normalized
        case let dictionary as [String: Any]:
            return dictionary.mapValues { normalize($0, workspaceRoot: workspaceRoot) }
        case let array as [Any]:
            return array.map { normalize($0, workspaceRoot: workspaceRoot) }
        default:
            return value
        }
    }

    private static func collapseWhitespace(_ string: String) -> String {
        string
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

// MARK: - Signatures

public enum FlailSignatures {
    /// A stable identity for "what failed this turn", extracted from tool output. Identical failing
    /// tests produce identical signatures across turns; a different failing test produces a different
    /// one. Volatile decimals (durations like `0.132 seconds`) are masked so timing noise never makes
    /// the same failure look new. Returns nil when the output carries no failure-shaped lines.
    public static func failureSignature(fromToolOutput output: String) -> String? {
        let failureMarkers = ["error:", "FAILED", "failed", "XCTAssert", "fatal:", "Fatal error"]
        let lines = output
            .split(separator: "\n")
            .map(String.init)
            .filter { line in failureMarkers.contains { line.contains($0) } }
            .map(maskVolatileNumbers)
        guard !lines.isEmpty else { return nil }
        return String(lines.joined(separator: "\n").prefix(500))
    }

    /// Mask decimal numbers (durations, fractional seconds) while keeping integers — `App.swift:10`
    /// is failure identity; `(0.132 seconds)` is noise.
    static func maskVolatileNumbers(_ line: String) -> String {
        var result = ""
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if character.isNumber {
                var end = index
                var sawDot = false
                while end < line.endIndex, line[end].isNumber || (line[end] == "." && !sawDot) {
                    if line[end] == "." {
                        // Only a dot followed by a digit makes a decimal (not a sentence period).
                        let next = line.index(after: end)
                        guard next < line.endIndex, line[next].isNumber else { break }
                        sawDot = true
                    }
                    end = line.index(after: end)
                }
                result += sawDot ? "#" : line[index..<end]
                index = end
            } else {
                result.append(character)
                index = line.index(after: index)
            }
        }
        return result
    }
}

// MARK: - Records and verdicts

/// One tool turn as the detector sees it. `deltaSignature` is an opaque summary of the workspace
/// change the turn produced ("" = nothing changed); `failureSignature` identifies a failure the turn
/// surfaced (nil = none). The wiring layer computes both.
public struct FlailTurnRecord: Sendable, Hashable {
    public var fingerprints: [ToolCallFingerprint]
    public var deltaSignature: String
    public var failureSignature: String?

    public init(fingerprints: [ToolCallFingerprint], deltaSignature: String = "", failureSignature: String? = nil) {
        self.fingerprints = fingerprints
        self.deltaSignature = deltaSignature
        self.failureSignature = failureSignature
    }
}

public struct FlailStuckReason: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        case repeatedActionNoProgress
        case repeatedFailure
        case pingPong
    }

    public var kind: Kind
    /// Human-readable, notification-ready: "Ran the same tool call 3× with no workspace change."
    public var message: String
}

public enum FlailVerdict: Sendable, Hashable {
    case none
    case suspected(FlailStuckReason)
    case confirmed(FlailStuckReason)
}

// MARK: - Detector

public struct FlailDetector: Sendable {
    /// Consecutive matching turns before a rule fires.
    public var repeatThreshold: Int
    /// History bound; also the widest lookback any rule uses.
    public var windowSize: Int

    private var history: [FlailTurnRecord] = []
    private var assessmentInjected = false

    public init(repeatThreshold: Int = 3, windowSize: Int = 6) {
        self.repeatThreshold = max(2, repeatThreshold)
        self.windowSize = max(self.repeatThreshold, windowSize)
    }

    /// Feed one completed tool turn; get the current verdict.
    public mutating func record(_ turn: FlailTurnRecord) -> FlailVerdict {
        history.append(turn)
        if history.count > windowSize {
            history.removeFirst(history.count - windowSize)
        }

        guard let reason = detectReason() else {
            // Genuine progress — a fresh, non-empty delta with no rule firing — clears the strike, so
            // the NEXT flail episode starts over at `.suspected` instead of jumping to `.confirmed`.
            if turn.deltaSignature != "", history.dropLast().last?.deltaSignature != turn.deltaSignature {
                assessmentInjected = false
            }
            return .none
        }
        return assessmentInjected ? .confirmed(reason) : .suspected(reason)
    }

    /// The wiring layer calls this when it injects the one self-assessment turn, arming escalation.
    public mutating func recordAssessment() {
        assessmentInjected = true
    }

    private func detectReason() -> FlailStuckReason? {
        if let reason = repeatedActionNoProgress() { return reason }
        if let reason = repeatedFailure() { return reason }
        if let reason = pingPong() { return reason }
        return nil
    }

    /// The same tool call(s), `repeatThreshold` turns in a row, none of them changing the workspace.
    private func repeatedActionNoProgress() -> FlailStuckReason? {
        let tail = history.suffix(repeatThreshold)
        guard tail.count == repeatThreshold, let first = tail.first else { return nil }
        guard !first.fingerprints.isEmpty else { return nil }
        guard tail.allSatisfy({ $0.fingerprints == first.fingerprints && $0.deltaSignature.isEmpty }) else {
            return nil
        }
        return FlailStuckReason(
            kind: .repeatedActionNoProgress,
            message: repeatedActionMessage(toolCallCount: first.fingerprints.count)
        )
    }

    private func repeatedActionMessage(toolCallCount: Int) -> String {
        let noun = toolCallCount == 1 ? "tool call" : "tool calls"
        return "Ran the same \(noun) \(repeatThreshold)× in a row with no workspace change."
    }

    /// The identical failure, `repeatThreshold` turns in a row — edits are happening, learning is not.
    private func repeatedFailure() -> FlailStuckReason? {
        let tail = history.suffix(repeatThreshold)
        guard tail.count == repeatThreshold, let signature = tail.first?.failureSignature else { return nil }
        guard tail.allSatisfy({ $0.failureSignature == signature }) else { return nil }
        let headline = signature.split(separator: "\n").first.map(String.init) ?? signature
        return FlailStuckReason(
            kind: .repeatedFailure,
            message: "Hit the identical failure \(repeatThreshold)× in a row: \(headline)"
        )
    }

    /// Workspace deltas alternating A,B,A,B — an edit/undo ping-pong that never converges.
    private func pingPong() -> FlailStuckReason? {
        let tail = Array(history.suffix(4))
        guard tail.count == 4 else { return nil }
        let a = tail[0].deltaSignature
        let b = tail[1].deltaSignature
        guard !a.isEmpty, !b.isEmpty, a != b else { return nil }
        guard tail[2].deltaSignature == a, tail[3].deltaSignature == b else { return nil }
        return FlailStuckReason(
            kind: .pingPong,
            message: "Alternating between two workspace states (edit/undo ping-pong) for 4 turns."
        )
    }
}
