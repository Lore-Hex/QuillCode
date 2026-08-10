import XCTest
@testable import QuillCodeCore

final class ThreadEventLogCompactorTests: XCTestCase {
    func testAlreadyCompactHistoryPreservesCopyOnWriteStorage() {
        let events = (0..<25_000).flatMap { index in
            [
                ThreadEvent(kind: .notice, summary: "Thinking: step \(index)"),
                ThreadEvent(kind: .toolCompleted, summary: "Completed step \(index)"),
            ]
        }
        let originalStorage = events.withUnsafeBufferPointer { buffer in
            UInt(bitPattern: buffer.baseAddress)
        }

        let compacted = ThreadEventLogCompactor.compact(events)

        let compactedStorage = compacted.withUnsafeBufferPointer { buffer in
            UInt(bitPattern: buffer.baseAddress)
        }
        XCTAssertEqual(compacted.count, events.count)
        XCTAssertEqual(compactedStorage, originalStorage)
    }

    func testCollapsesLargeConsecutiveReasoningBurstToLatestNotice() throws {
        let reasoning = (0..<50_000).map { index in
            ThreadEvent(kind: .notice, summary: "Thinking: token \(index)")
        }
        let latestReasoningID = try XCTUnwrap(reasoning.last?.id)
        let events = [
            ThreadEvent(kind: .message, summary: "Start"),
            ThreadEvent(kind: .notice, summary: "Streaming model response"),
        ] + reasoning + [
            ThreadEvent(kind: .toolQueued, summary: "host.shell.run queued"),
        ]

        let compacted = ThreadEventLogCompactor.compact(events)

        XCTAssertEqual(compacted.count, 4)
        XCTAssertEqual(compacted[2].id, latestReasoningID)
        XCTAssertEqual(compacted[2].summary, "Thinking: token 49999")
    }

    func testKeepsOneReasoningNoticePerBurstAndPreservesSemanticEvents() {
        let firstLatest = ThreadEvent(kind: .notice, summary: "Thinking: first complete thought")
        let secondLatest = ThreadEvent(kind: .notice, summary: "Thinking: second complete thought")
        let events = [
            ThreadEvent(kind: .notice, summary: "Thinking: first"),
            firstLatest,
            ThreadEvent(kind: .toolQueued, summary: "queued"),
            ThreadEvent(kind: .toolRunning, summary: "running"),
            ThreadEvent(kind: .notice, summary: "Thinking: second"),
            secondLatest,
            ThreadEvent(kind: .approvalRequested, summary: "approve"),
            ThreadEvent(kind: .reviewComment, summary: "review"),
            ThreadEvent(kind: .notice, summary: "ordinary notice"),
            ThreadEvent(kind: .message, summary: "done"),
        ]

        let compacted = ThreadEventLogCompactor.compact(events)

        XCTAssertEqual(compacted.map(\.id), [
            firstLatest.id,
            events[2].id,
            events[3].id,
            secondLatest.id,
            events[6].id,
            events[7].id,
            events[8].id,
            events[9].id,
        ])
    }
}
