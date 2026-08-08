import Foundation
import XCTest

final class ParityFounderTaskCatalogTests: QuillCodeParityTestCase {
    func testFounderCatalogAddsTenLongHorizonTasksToVerifiedWaveFive() throws {
        let catalogURL = Self.packageRoot()
            .appendingPathComponent("docs/founder-task-additions.json")
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any]
        )
        let rows = try XCTUnwrap(object["rows"] as? [[String: Any]])
        let categoryCounts = try XCTUnwrap(object["categoryCounts"] as? [String: Int])

        XCTAssertEqual(object["version"] as? Int, 1)
        XCTAssertEqual(object["reviewDate"] as? String, "2026-08-08")
        XCTAssertEqual(object["startID"] as? Int, 211)
        XCTAssertEqual(object["endID"] as? Int, 320)
        XCTAssertEqual(object["rowCount"] as? Int, 110)
        XCTAssertEqual(rows.compactMap { $0["ID"] as? Int }, Array(211...320))
        XCTAssertEqual(categoryCounts.count, 10)
        XCTAssertTrue(categoryCounts.values.allSatisfy { $0 == 11 })

        let verifiedRows = Array(rows.prefix(100))
        XCTAssertTrue(verifiedRows.allSatisfy { $0["Status"] as? String == "Verified end-to-end" })
        XCTAssertTrue(verifiedRows.allSatisfy {
            guard let evidence = $0["Evidence / gap"] as? String else { return false }
            return evidence.contains("deepseek/deepseek-v4-flash-0731")
                && evidence.contains("passed 100/100")
                && evidence.contains("full-r74")
        })

        let longHorizonRows = Array(rows.suffix(10))
        XCTAssertEqual(longHorizonRows.compactMap { $0["ID"] as? Int }, Array(311...320))
        XCTAssertTrue(longHorizonRows.allSatisfy {
            $0["Wave"] as? String == "Wave 6 - long-horizon YC founder workflows"
                && $0["Status"] as? String == "Proposed - not yet driven"
                && $0["Capability needed"] as? String == "Browser pane"
        })
        XCTAssertTrue(longHorizonRows.allSatisfy {
            guard let task = $0["Task (what the person types)"] as? String,
                  let evidence = $0["Evidence / gap"] as? String else { return false }
            return task.contains("LinkedIn")
                && task.contains("read-only mode")
                && task.contains("progress.md")
                && task.contains("outputs/")
                && (task.contains("continue until") || task.contains("finish all minima"))
                && task.count >= 1_200
                && evidence.contains("PENDING long-horizon native Cowork run")
                && evidence.contains("deepseek/deepseek-v4-flash-0731")
        })

        let prompts = rows.compactMap { $0["Task (what the person types)"] as? String }
        XCTAssertEqual(prompts.count, 110)
        XCTAssertEqual(Set(prompts).count, 110)
        let incidentTabletop = try XCTUnwrap(
            rows.first { $0["ID"] as? Int == 298 }?["Task (what the person types)"] as? String
        )
        XCTAssertTrue(incidentTabletop.contains("accidental service outage"))
        XCTAssertTrue(incidentTabletop.contains("business continuity, restoration, and communications planning"))
        XCTAssertFalse(incidentTabletop.lowercased().contains("offensive security"))
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
        XCTAssertTrue(result.output.contains("110 tasks, IDs 211-320"), result.output)
    }

    func testCanonicalSnapshotIncludesFounderExpansion() throws {
        let snapshotURL = Self.packageRoot()
            .appendingPathComponent("docs/coworker-task-catalog.json")
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: snapshotURL)) as? [String: Any]
        )
        let rows = try XCTUnwrap(object["rows"] as? [[String: Any]])
        let taskIDs = try XCTUnwrap(object["taskIDs"] as? [Int])

        XCTAssertEqual(object["reviewDate"] as? String, "2026-08-08")
        XCTAssertEqual(object["rowCount"] as? Int, 320)
        XCTAssertEqual(taskIDs, Array(1...320))
        XCTAssertEqual(rows.last?["id"] as? Int, 320)
        XCTAssertEqual(rows.last?["category"] as? String, "Pricing & Competitive Intelligence")

        let founderRows = rows.filter { ($0["id"] as? Int ?? 0) >= 211 }
        XCTAssertEqual(founderRows.count, 110)
        XCTAssertTrue(founderRows.prefix(100).allSatisfy {
            $0["sourceStatus"] as? String == "Verified end-to-end"
                && $0["quillCodeCoverage"] as? String == "Covered by existing core/tool analogue"
                && $0["lastQuillCodeReview"] as? String == "2026-08-07"
        })
        XCTAssertTrue(founderRows.suffix(10).allSatisfy {
            $0["sourceStatus"] as? String == "Proposed - not yet driven"
                && $0["quillCodeCoverage"] as? String == "Needs QuillCode validation"
                && $0["lastQuillCodeReview"] as? String == "2026-08-08"
        })

        let sourceStatusCounts = try XCTUnwrap(object["sourceStatusCounts"] as? [String: Int])
        let coverageCounts = try XCTUnwrap(object["quillCodeCoverageCounts"] as? [String: Int])
        XCTAssertEqual(sourceStatusCounts["Verified end-to-end"], 216)
        XCTAssertEqual(sourceStatusCounts["Proposed - not yet driven"], 14)
        XCTAssertEqual(coverageCounts["Covered by existing core/tool analogue"], 241)
        XCTAssertEqual(coverageCounts["Needs QuillCode validation"], 62)
    }
}
