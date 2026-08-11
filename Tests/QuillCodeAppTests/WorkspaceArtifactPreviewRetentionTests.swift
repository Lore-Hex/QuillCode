import Foundation
import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceArtifactPreviewRetentionTests: XCTestCase {
    func testRetentionKeepsOnlyNewestBoundedTextPreviews() throws {
        let directory = try makeQuillCodeTestDirectory()
        var cards: [ToolCardState] = []
        for index in 0..<14 {
            let file = directory.appendingPathComponent("artifact-\(index).txt")
            try "preview \(index)\n".write(to: file, atomically: true, encoding: .utf8)
            cards.append(card(id: "card-\(index)", artifact: file.path, textPreview: "stale"))
        }

        WorkspaceArtifactPreviewRetention.hydrate(&cards)

        let hydratedIndices = cards.indices.filter {
            cards[$0].artifacts.first?.textPreview != nil
        }
        XCTAssertEqual(hydratedIndices, Array(6..<14))
        XCTAssertEqual(
            cards.flatMap(\.artifacts).compactMap(\.textPreview).count,
            WorkspaceArtifactPreviewRetention.textPreviewLimit
        )
        XCTAssertLessThanOrEqual(
            cards.flatMap(\.artifacts).compactMap(\.textPreview).reduce(0) { $0 + $1.utf8.count },
            WorkspaceArtifactPreviewRetention.textPreviewByteLimit
        )
        XCTAssertTrue(cards.prefix(6).allSatisfy { $0.artifacts.first?.textPreview == nil })
        XCTAssertEqual(cards.last?.artifacts.first?.textPreview, "preview 13\n")
        XCTAssertEqual(cards.first?.artifacts.first?.value, directory.appendingPathComponent("artifact-0.txt").path)
    }

    func testProjectionHydratesTimelineAndToolCardsFromSameRecentBudget() throws {
        let directory = try makeQuillCodeTestDirectory()
        var events: [ThreadEvent] = []
        for index in 0..<10 {
            let file = directory.appendingPathComponent("result-\(index).txt")
            try "result \(index)\n".write(to: file, atomically: true, encoding: .utf8)
            let call = ToolCall(
                id: "call-\(index)",
                name: ToolDefinition.fileRead.name,
                argumentsJSON: ToolArguments.json(["path": file.path])
            )
            let result = ToolResult(ok: true, stdout: "read", artifacts: [file.path])
            events.append(ThreadEvent(
                kind: .toolQueued,
                summary: "queued",
                payloadJSON: try JSONHelpers.encodePretty(call)
            ))
            events.append(ThreadEvent(
                kind: .toolCompleted,
                summary: "completed",
                payloadJSON: try JSONHelpers.encodePretty(result)
            ))
        }

        let projection = WorkspaceTranscriptSurfaceBuilder(thread: ChatThread(events: events)).projection()
        let timelineCards = projection.timelineItems.compactMap(\.toolCard)

        XCTAssertEqual(projection.toolCards.count, 10)
        XCTAssertEqual(timelineCards.count, 10)
        XCTAssertTrue(projection.toolCards.prefix(2).allSatisfy { $0.artifacts.first?.textPreview == nil })
        XCTAssertEqual(
            projection.toolCards.suffix(8).compactMap { $0.artifacts.first?.textPreview }.count,
            8
        )
        XCTAssertEqual(
            projection.toolCards.map { $0.artifacts.first?.textPreview },
            timelineCards.map { $0.artifacts.first?.textPreview }
        )
    }

    func testRetentionBoundsArtifactInspectionWithinRecentCards() throws {
        let directory = try makeQuillCodeTestDirectory()
        var artifacts = (0..<WorkspaceArtifactPreviewRetention.artifactInspectionLimit).map {
            ToolArtifactState(value: directory.appendingPathComponent("opaque-\($0).bin").path)
        }
        let textFile = directory.appendingPathComponent("beyond-budget.txt")
        try "should stay lazy\n".write(to: textFile, atomically: true, encoding: .utf8)
        artifacts.append(ToolArtifactState(value: textFile.path, textPreview: "stale"))
        var cards = [ToolCardState(
            id: "many-artifacts",
            title: ToolDefinition.fileRead.name,
            subtitle: "Completed",
            status: .done,
            artifacts: artifacts
        )]

        WorkspaceArtifactPreviewRetention.hydrate(&cards)

        XCTAssertEqual(cards[0].artifacts.count, artifacts.count)
        XCTAssertNil(cards[0].artifacts.last?.textPreview)
        XCTAssertEqual(cards[0].artifacts.last?.value, textFile.path)
    }

    func testProjectionSynchronizesDuplicateToolIDsByTimelinePosition() throws {
        let directory = try makeQuillCodeTestDirectory()
        var events: [ThreadEvent] = []
        for index in 0..<2 {
            let file = directory.appendingPathComponent("duplicate-\(index).txt")
            try "duplicate \(index)\n".write(to: file, atomically: true, encoding: .utf8)
            let call = ToolCall(
                id: "reused-id",
                name: ToolDefinition.fileRead.name,
                argumentsJSON: ToolArguments.json(["path": file.path])
            )
            let result = ToolResult(ok: true, stdout: "read", artifacts: [file.path])
            events.append(ThreadEvent(
                kind: .toolQueued,
                summary: "queued",
                payloadJSON: try JSONHelpers.encodePretty(call)
            ))
            events.append(ThreadEvent(
                kind: .toolCompleted,
                summary: "completed",
                payloadJSON: try JSONHelpers.encodePretty(result)
            ))
        }

        let projection = WorkspaceTranscriptSurfaceBuilder(thread: ChatThread(events: events)).projection()
        let timelineCards = projection.timelineItems.compactMap(\.toolCard)

        XCTAssertEqual(
            projection.toolCards.map { $0.artifacts.first?.textPreview },
            ["duplicate 0\n", "duplicate 1\n"]
        )
        XCTAssertEqual(
            projection.toolCards.map { $0.artifacts.first?.textPreview },
            timelineCards.map { $0.artifacts.first?.textPreview }
        )
    }

    func testTextPreviewCacheInvalidatesWhenFileMetadataChanges() throws {
        let directory = try makeQuillCodeTestDirectory()
        let file = directory.appendingPathComponent("mutable.txt")
        try "first\n".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(ToolArtifactTextPreviewBuilder.textPreview(for: file.path), "first\n")

        try "other\n".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(5)],
            ofItemAtPath: file.path
        )
        XCTAssertEqual(ToolArtifactTextPreviewBuilder.textPreview(for: file.path), "other\n")

        try FileManager.default.removeItem(at: file)
        XCTAssertNil(ToolArtifactTextPreviewBuilder.textPreview(for: file.path))
    }

    private func card(id: String, artifact: String, textPreview: String?) -> ToolCardState {
        ToolCardState(
            id: id,
            title: ToolDefinition.fileRead.name,
            subtitle: "Completed",
            status: .done,
            artifacts: [ToolArtifactState(value: artifact, textPreview: textPreview)]
        )
    }
}
