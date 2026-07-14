import XCTest
import QuillCodeCore
@testable import QuillCodePersistence

final class AgentImportReceiptStoreTests: PersistenceTestCase {
    func testRecordUnionsCandidateIDsAndRoundTripsDate() throws {
        let file = try makeTempDirectory().appendingPathComponent("imports/receipts.json")
        let store = AgentImportReceiptStore(fileURL: file)
        let firstDate = Date(timeIntervalSince1970: 100)
        let secondDate = Date(timeIntervalSince1970: 200)

        try store.record(["one"], source: .claudeCode, at: firstDate)
        try store.record(["two"], source: .claudeCode, at: secondDate)

        let receipt = store.load(source: .claudeCode)
        XCTAssertEqual(receipt.candidateIDs, ["one", "two"])
        XCTAssertEqual(receipt.updatedAt, secondDate)
        XCTAssertEqual(try posixPermissions(at: file.deletingLastPathComponent()), 0o700)
    }

    func testCorruptReceiptFailsClosedAsEmpty() throws {
        let file = try makeTempDirectory().appendingPathComponent("receipts.json")
        try Data("not-json".utf8).write(to: file)

        let receipt = AgentImportReceiptStore(fileURL: file).load(source: .claudeCode)

        XCTAssertEqual(receipt.candidateIDs, [])
    }
}
