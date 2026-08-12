import Foundation

/// Keeps provider token cadence separate from presentation cadence. The desktop projects progress
/// every 50 ms; rebuilding a growing answer and a full thread more often only creates quadratic
/// parsing/copying work that cannot become visible. The first usable text remains immediate and the
/// terminal path always forces the newest preview through.
struct AgentVisibleAssistantPreviewCadence {
    private let minimumIntervalNanoseconds: UInt64
    private var actionType: String?
    private var lastInspectionNanoseconds: UInt64?
    private var lastPublishedText = ""

    init(minimumIntervalNanoseconds: UInt64) {
        self.minimumIntervalNanoseconds = minimumIntervalNanoseconds
    }

    mutating func nextPreview(from rawActionText: String, nowNanoseconds: UInt64) -> String? {
        if actionType == nil {
            actionType = AgentActionStreamPreview.streamedActionType(from: rawActionText)
        }
        guard actionType == "say" else { return nil }
        if let lastInspectionNanoseconds,
           nowNanoseconds >= lastInspectionNanoseconds,
           nowNanoseconds - lastInspectionNanoseconds < minimumIntervalNanoseconds {
            return nil
        }
        return inspect(rawActionText, nowNanoseconds: nowNanoseconds)
    }

    mutating func finalPreview(from rawActionText: String) -> String? {
        if actionType == nil {
            actionType = AgentActionStreamPreview.streamedActionType(from: rawActionText)
        }
        guard actionType == "say" else { return nil }
        return inspect(rawActionText, nowNanoseconds: nil)
    }

    private mutating func inspect(
        _ rawActionText: String,
        nowNanoseconds: UInt64?
    ) -> String? {
        guard let visibleText = AgentActionStreamPreview
            .visibleAssistantTextForKnownSayAction(from: rawActionText),
              !visibleText.isEmpty
        else {
            return nil
        }
        if let nowNanoseconds {
            lastInspectionNanoseconds = nowNanoseconds
        }
        guard visibleText != lastPublishedText,
              !AgentPromisedWorkGuard.shouldSuppressStreamingPreview(for: visibleText)
        else {
            return nil
        }
        lastPublishedText = visibleText
        return visibleText
    }
}

enum AgentStreamingProgressCadence {
    static let minimumIntervalNanoseconds: UInt64 = 50_000_000
}
