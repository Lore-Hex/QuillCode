import Foundation

/// A bounded progress snapshot emitted while one tool call is still running.
///
/// `completed` and `total` preserve the provider's native units. Presentation layers derive a
/// fraction only when `total` is positive, so count-, byte-, and percentage-based tools share the
/// same contract without guessing units.
public struct ToolExecutionProgress: Codable, Sendable, Hashable {
    public var completed: Double
    public var total: Double?
    public var message: String?

    public init(completed: Double, total: Double? = nil, message: String? = nil) {
        self.completed = completed
        self.total = total
        self.message = message
    }

    public var fractionCompleted: Double? {
        guard completed.isFinite,
              let total,
              total.isFinite,
              total > 0
        else {
            return nil
        }
        return min(max(completed / total, 0), 1)
    }
}

/// Transcript payload associating a progress update with the exact tool card it updates.
public struct ToolProgressEventPayload: Codable, Sendable, Hashable {
    public var toolCallID: String
    public var progress: ToolExecutionProgress

    public init(toolCallID: String, progress: ToolExecutionProgress) {
        self.toolCallID = toolCallID
        self.progress = progress
    }
}
