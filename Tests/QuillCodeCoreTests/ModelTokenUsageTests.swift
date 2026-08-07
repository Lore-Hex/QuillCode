import XCTest
@testable import QuillCodeCore

final class ModelTokenUsageTests: XCTestCase {
    func testDecodesOpenAIStyleUsage() throws {
        let data = #"{"prompt_tokens":1200,"completion_tokens":340,"total_tokens":1540}"#
            .data(using: .utf8)!

        let usage = try JSONDecoder().decode(ModelTokenUsage.self, from: data)

        XCTAssertEqual(usage.promptTokens, 1200)
        XCTAssertEqual(usage.completionTokens, 340)
        XCTAssertEqual(usage.totalTokens, 1540)
        XCTAssertEqual(usage.contextTokens, 1540)
    }

    func testDecodesInputOutputUsageAndComputesTotal() throws {
        let data = #"{"input_tokens":80,"output_tokens":20}"#
            .data(using: .utf8)!

        let usage = try JSONDecoder().decode(ModelTokenUsage.self, from: data)

        XCTAssertEqual(usage.promptTokens, 80)
        XCTAssertEqual(usage.completionTokens, 20)
        XCTAssertEqual(usage.totalTokens, 100)
    }

    func testDecodesStringBackedTokenCounts() throws {
        let data = #"{"prompt_tokens":"120.0","completion_tokens":"30","total_tokens":"150"}"#
            .data(using: .utf8)!

        let usage = try JSONDecoder().decode(ModelTokenUsage.self, from: data)

        XCTAssertEqual(usage.promptTokens, 120)
        XCTAssertEqual(usage.completionTokens, 30)
        XCTAssertEqual(usage.totalTokens, 150)
    }

    func testUsageEventRoundTripsThroughThreadEventPayload() throws {
        let usage = ModelTokenUsage(promptTokens: 10, completionTokens: 2, totalTokens: 12)
        let event = ModelTokenUsageEvent.event(usage: usage, modelID: " /prometheus ", callCount: 7)

        XCTAssertEqual(event.kind, .notice)
        XCTAssertEqual(event.summary, ModelTokenUsageEvent.summary)
        XCTAssertEqual(ModelTokenUsageEvent.usage(from: event), usage)
        XCTAssertEqual(ModelTokenUsageEvent.record(from: event)?.modelID, TrustedRouterDefaults.prometheusModel)
        XCTAssertEqual(ModelTokenUsageEvent.record(from: event)?.callCount, 7)
    }

    func testUsageEventReadsLegacyUsagePayload() throws {
        let usage = ModelTokenUsage(promptTokens: 10, completionTokens: 2, totalTokens: 12)
        let event = ThreadEvent(
            kind: .notice,
            summary: ModelTokenUsageEvent.summary,
            payloadJSON: try JSONHelpers.encodePretty(usage)
        )

        XCTAssertEqual(ModelTokenUsageEvent.usage(from: event), usage)
        XCTAssertEqual(ModelTokenUsageEvent.record(from: event)?.usage, usage)
        XCTAssertNil(ModelTokenUsageEvent.record(from: event)?.modelID)
        XCTAssertEqual(ModelTokenUsageEvent.record(from: event)?.callCount, 1)
    }

    func testStructuredRecordDefaultsLegacyCallCountAndOmitsOrdinaryCountWhenEncoding() throws {
        let legacyData = #"{"usage":{"promptTokens":10,"completionTokens":2,"totalTokens":12},"modelID":"acme/agent"}"#
            .data(using: .utf8)!

        let record = try JSONDecoder().decode(ModelTokenUsageRecord.self, from: legacyData)
        let encoded = try JSONEncoder().encode(record)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertEqual(record.callCount, 1)
        XCTAssertNil(object["callCount"], "ordinary usage receipts should not grow on disk")
    }
}
