import XCTest
import QuillCodeAgent
import QuillCodeCore
@testable import QuillCodeApp

/// Compaction and fork summaries are auxiliary calls: they must run on the cheap catalog model the
/// selector picks, leave the thread's own (flagship) model untouched, and record the choice in the
/// continuation telemetry.
@MainActor
final class WorkspaceAuxiliaryModelSelectionTests: XCTestCase {
    func testCompactContextRoutesSummaryToCheapCatalogModel() async throws {
        let source = sourceThread(model: "acme/flagship")
        let generator = RecordingContextSummaryGenerator()
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                threads: [source],
                selectedThreadID: source.id,
                modelCatalog: pricedCatalog()
            ),
            contextSummaryGenerator: generator
        )

        let compactCandidate = await model.compactContextWithConfiguredSummary(sourceID: source.id)
        let compactID = try XCTUnwrap(compactCandidate)
        let compacted = try XCTUnwrap(model.root.threads.first { $0.id == compactID })

        let recordedRequest = await generator.lastRequest
        let request = try XCTUnwrap(recordedRequest)
        XCTAssertEqual(request.modelID, "acme/tiny-mini")
        // The auxiliary choice never leaks into the conversation's model.
        XCTAssertEqual(compacted.model, "acme/flagship")
        XCTAssertEqual(model.root.threads.first { $0.id == source.id }?.model, "acme/flagship")
        let telemetry = try XCTUnwrap(decodeTelemetry(from: compacted))
        XCTAssertEqual(telemetry.modelID, "acme/tiny-mini")
        XCTAssertEqual(telemetry.modelSelectionSource, .catalogHeuristic)
    }

    func testForkSummaryRoutesSummaryToCheapCatalogModel() async throws {
        let source = sourceThread(model: "acme/flagship")
        let generator = RecordingContextSummaryGenerator()
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                threads: [source],
                selectedThreadID: source.id,
                modelCatalog: pricedCatalog()
            ),
            contextSummaryGenerator: generator
        )

        let forkCandidate = await model.forkThreadWithConfiguredSummary(
            sourceID: source.id,
            strategy: .summarizedContext
        )
        _ = try XCTUnwrap(forkCandidate)

        let recordedRequest = await generator.lastRequest
        let request = try XCTUnwrap(recordedRequest)
        XCTAssertEqual(request.modelID, "acme/tiny-mini")
    }

    func testCompactContextFallsBackToSessionModelWhenCatalogHasNoPrices() async throws {
        let source = sourceThread(model: "z-ai/glm-5.2")
        let generator = RecordingContextSummaryGenerator()
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [source], selectedThreadID: source.id),
            contextSummaryGenerator: generator
        )

        let compactCandidate = await model.compactContextWithConfiguredSummary(sourceID: source.id)
        let compactID = try XCTUnwrap(compactCandidate)
        let compacted = try XCTUnwrap(model.root.threads.first { $0.id == compactID })

        let recordedRequest = await generator.lastRequest
        let request = try XCTUnwrap(recordedRequest)
        XCTAssertEqual(request.modelID, "z-ai/glm-5.2")
        let telemetry = try XCTUnwrap(decodeTelemetry(from: compacted))
        XCTAssertEqual(telemetry.modelID, "z-ai/glm-5.2")
        XCTAssertEqual(telemetry.modelSelectionSource, .sessionModelFallback)
    }

    private func decodeTelemetry(from thread: ChatThread) throws -> WorkspaceContextSummaryTelemetry? {
        guard let payload = thread.events.last?.payloadJSON else { return nil }
        return try JSONDecoder().decode(WorkspaceContextSummaryTelemetry.self, from: Data(payload.utf8))
    }

    private func sourceThread(model: String) -> ChatThread {
        ChatThread(
            title: "Long context",
            model: model,
            messages: [
                .init(role: .user, content: "old task"),
                .init(role: .assistant, content: "old result"),
                .init(role: .user, content: "latest task"),
                .init(role: .assistant, content: "latest result")
            ]
        )
    }

    private func pricedCatalog() -> [ModelInfo] {
        [
            ModelInfo(
                id: "acme/flagship",
                provider: "acme",
                displayName: "Flagship",
                category: "acme",
                capabilities: ModelCapabilities(
                    inputPricePerMillionTokens: 15,
                    outputPricePerMillionTokens: 75,
                    outputModalities: ["text"]
                )
            ),
            ModelInfo(
                id: "acme/tiny-mini",
                provider: "acme",
                displayName: "Tiny Mini",
                category: "acme",
                capabilities: ModelCapabilities(
                    inputPricePerMillionTokens: 0.1,
                    outputPricePerMillionTokens: 0.4,
                    outputModalities: ["text"]
                )
            )
        ]
    }
}

private actor SummaryRequestRecorder {
    private(set) var lastRequest: WorkspaceContextSummaryRequest?

    func record(_ request: WorkspaceContextSummaryRequest) {
        lastRequest = request
    }
}

private struct RecordingContextSummaryGenerator: WorkspaceContextSummaryGenerating {
    var isModelBacked: Bool { true }
    private let recorder = SummaryRequestRecorder()

    var lastRequest: WorkspaceContextSummaryRequest? {
        get async { await recorder.lastRequest }
    }

    func summary(for request: WorkspaceContextSummaryRequest) async throws -> String {
        await recorder.record(request)
        return "Keep the architecture decisions and open tasks."
    }
}
