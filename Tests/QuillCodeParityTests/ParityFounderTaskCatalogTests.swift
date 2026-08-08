import Foundation
import XCTest

final class ParityFounderTaskCatalogTests: QuillCodeParityTestCase {
    func testFounderCatalogAddsOneHundredBalancedContiguousTasks() throws {
        let catalogURL = Self.packageRoot()
            .appendingPathComponent("docs/founder-task-additions.json")
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any]
        )
        let rows = try XCTUnwrap(object["rows"] as? [[String: Any]])
        let categoryCounts = try XCTUnwrap(object["categoryCounts"] as? [String: Int])

        XCTAssertEqual(object["version"] as? Int, 1)
        XCTAssertEqual(object["reviewDate"] as? String, "2026-08-06")
        XCTAssertEqual(object["startID"] as? Int, 211)
        XCTAssertEqual(object["endID"] as? Int, 310)
        XCTAssertEqual(object["rowCount"] as? Int, 100)
        XCTAssertEqual(rows.compactMap { $0["ID"] as? Int }, Array(211...310))
        XCTAssertEqual(categoryCounts.count, 10)
        XCTAssertTrue(categoryCounts.values.allSatisfy { $0 == 10 })

        let prompts = rows.compactMap { $0["Task (what the person types)"] as? String }
        XCTAssertEqual(prompts.count, 100)
        XCTAssertEqual(Set(prompts).count, 100)
        let incidentTabletop = try XCTUnwrap(
            rows.first { $0["ID"] as? Int == 298 }?["Task (what the person types)"] as? String
        )
        XCTAssertTrue(incidentTabletop.contains("authorized, defensive"))
        XCTAssertTrue(incidentTabletop.contains("planning and documentation only"))
        XCTAssertTrue(incidentTabletop.contains("do not perform or describe offensive security actions"))
        let requiredColumns = Set([
            "ID", "Wave", "Status", "Category", "Task (what the person types)", "Role",
            "Capability needed", "They must supply", "Why it saves time", "Evidence / gap",
        ])
        XCTAssertTrue(rows.allSatisfy { requiredColumns.isSubset(of: Set($0.keys)) })
    }

    func testFounderCatalogGeneratorMatchesCheckedInContract() throws {
        let result = try Self.runPython(
            Self.packageRoot().appendingPathComponent("scripts/founder-task-catalog.py"),
            arguments: ["--check"]
        )
        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("100 tasks, IDs 211-310"), result.output)
    }

    func testCanonicalSnapshotIncludesFounderExpansion() throws {
        let snapshotURL = Self.packageRoot()
            .appendingPathComponent("docs/coworker-task-catalog.json")
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: snapshotURL)) as? [String: Any]
        )
        let rows = try XCTUnwrap(object["rows"] as? [[String: Any]])
        let taskIDs = try XCTUnwrap(object["taskIDs"] as? [Int])

        XCTAssertEqual(object["reviewDate"] as? String, "2026-08-06")
        XCTAssertEqual(object["rowCount"] as? Int, 310)
        XCTAssertEqual(taskIDs, Array(1...310))
        XCTAssertEqual(rows.last?["id"] as? Int, 310)
        XCTAssertEqual(rows.last?["category"] as? String, "Pricing & Competitive Intelligence")
    }
}
