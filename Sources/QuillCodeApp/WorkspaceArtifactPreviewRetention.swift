import Foundation

enum WorkspaceArtifactPreviewRetention {
    static let recentToolCardLimit = 12
    static let artifactInspectionLimit = 48
    static let textPreviewLimit = 8
    static let textPreviewByteLimit = 64 * 1024

    static func hydrate(_ cards: inout [ToolCardState]) {
        for cardIndex in cards.indices {
            for artifactIndex in cards[cardIndex].artifacts.indices {
                cards[cardIndex].artifacts[artifactIndex].textPreview = nil
            }
        }

        var hydratedCount = 0
        var hydratedBytes = 0
        var inspectedCount = 0
        let firstRecentIndex = max(cards.count - recentToolCardLimit, 0)
        guard firstRecentIndex < cards.count else { return }

        for cardIndex in stride(from: cards.count - 1, through: firstRecentIndex, by: -1) {
            for artifactIndex in cards[cardIndex].artifacts.indices {
                guard inspectedCount < artifactInspectionLimit,
                      hydratedCount < textPreviewLimit
                else {
                    break
                }
                inspectedCount += 1
                guard let preview = ToolArtifactTextPreviewBuilder.textPreview(
                          for: cards[cardIndex].artifacts[artifactIndex].value
                      )
                else {
                    continue
                }
                let previewBytes = preview.utf8.count
                guard previewBytes <= textPreviewByteLimit - hydratedBytes else {
                    continue
                }
                cards[cardIndex].artifacts[artifactIndex].textPreview = preview
                hydratedCount += 1
                hydratedBytes += previewBytes
            }
            if inspectedCount == artifactInspectionLimit
                || hydratedCount == textPreviewLimit
                || hydratedBytes == textPreviewByteLimit {
                break
            }
        }
    }

    static func hydrate(_ projection: inout WorkspaceTranscriptProjectionAccumulator) {
        let timelineCardIndices = projection.timelineItems.indices.filter {
            projection.timelineItems[$0].toolCard != nil
        }
        var timelineCards = timelineCardIndices.compactMap {
            projection.timelineItems[$0].toolCard
        }
        hydrate(&timelineCards)

        for (timelineIndex, card) in zip(timelineCardIndices, timelineCards) {
            projection.timelineItems[timelineIndex] = .toolCard(card)
        }
        projection.synchronizeToolCardsFromTimeline()
    }
}
