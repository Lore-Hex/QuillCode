import Foundation
import XCTest
@testable import QuillCodeCore

final class SubagentPersistenceModelsTests: XCTestCase {
    func testRunManifestRoundTripsEveryDurableField() throws {
        let runID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let threadID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let payloadKey = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_100)
        let approval = SubagentPendingApproval(
            requestID: "approval-1",
            generation: 2,
            payloadKey: payloadKey,
            createdAt: createdAt,
            phase: .executing
        )
        let worker = SubagentWorkerRecord(
            id: "worker-1",
            childThreadID: threadID,
            dependencyIDs: ["worker-0"],
            name: "Verifier",
            role: "Run focused tests",
            groupPath: ["Build"],
            depth: 1,
            attempt: 3,
            status: .interrupted,
            summary: "Interrupted during restart",
            pendingApproval: approval,
            updatedAt: updatedAt
        )
        let record = SubagentRunRecord(
            id: runID,
            objective: "Ship durable subagents",
            maxConcurrentWorkers: 2,
            maxDepth: 4,
            maxTotalJobs: 32,
            workers: [worker],
            lastPublishedSummary: "One worker paused",
            createdAt: createdAt,
            updatedAt: updatedAt,
            finishedAt: nil
        )

        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(SubagentRunRecord.self, from: data)

        XCTAssertEqual(decoded, record)
        XCTAssertEqual(decoded.worker(id: "worker-1"), worker)
        XCTAssertNil(decoded.worker(id: "missing"))
    }

    func testDefaultInitializersProduceRunnableManifest() {
        let worker = SubagentWorkerRecord(name: "Research", role: "Inspect the project")
        let run = SubagentRunRecord(objective: "Understand the code", workers: [worker])
        let approval = SubagentPendingApproval(requestID: "approval-default")

        XCTAssertEqual(worker.dependencyIDs, [])
        XCTAssertEqual(worker.groupPath, [])
        XCTAssertEqual(worker.depth, 0)
        XCTAssertEqual(worker.attempt, 1)
        XCTAssertEqual(worker.status, .queued)
        XCTAssertEqual(run.maxDepth, 3)
        XCTAssertEqual(run.maxTotalJobs, 64)
        XCTAssertNil(run.maxConcurrentWorkers)
        XCTAssertEqual(approval.generation, 0)
        XCTAssertEqual(approval.phase, .pending)
    }

    func testThreadRoundTripsCompactSubagentManifest() throws {
        let worker = SubagentWorkerRecord(
            id: "worker-1",
            name: "Implementer",
            role: "Edit files",
            status: .awaitingApproval,
            pendingApproval: SubagentPendingApproval(requestID: "approval-1")
        )
        let run = SubagentRunRecord(objective: "Implement persistence", workers: [worker])
        let thread = ChatThread(title: "Parent", subagentRuns: [run])

        let data = try JSONEncoder().encode(thread)
        let decoded = try JSONDecoder().decode(ChatThread.self, from: data)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertEqual(decoded.subagentRuns, [run])
        XCTAssertFalse(json.contains("argumentsJSON"))
        XCTAssertFalse(json.contains("\"thread\":"))
    }

    func testThreadWrittenBeforeSubagentRunsDecodesToEmptyManifest() throws {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "title": "Legacy",
          "instructions": [],
          "memories": [],
          "mode": "auto",
          "model": "trustedrouter/fast",
          "messages": [],
          "events": [],
          "isPinned": false,
          "isArchived": false,
          "createdAt": "2020-01-01T00:00:00Z",
          "updatedAt": "2020-01-01T00:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let thread = try decoder.decode(ChatThread.self, from: Data(json.utf8))

        XCTAssertEqual(thread.subagentRuns, [])
    }

    func testEveryApprovalPhaseAndInterruptedStatusAreCodable() throws {
        for phase in SubagentApprovalPhase.allCases {
            let data = try JSONEncoder().encode(phase)
            XCTAssertEqual(try JSONDecoder().decode(SubagentApprovalPhase.self, from: data), phase)
        }
        let data = try JSONEncoder().encode(SubagentStatus.interrupted)
        XCTAssertEqual(try JSONDecoder().decode(SubagentStatus.self, from: data), .interrupted)
        XCTAssertEqual(SubagentStatus.interrupted.label, "Interrupted")
    }
}
