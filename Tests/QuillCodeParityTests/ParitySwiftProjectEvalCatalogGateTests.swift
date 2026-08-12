import Foundation
import XCTest

final class ParitySwiftProjectEvalCatalogGateTests: QuillCodeParityTestCase {
    func testSwiftProjectEvalCatalogKeepsTenRunnableDesktopScenarios() throws {
        let catalogURL = Self.packageRoot()
            .appendingPathComponent("docs")
            .appendingPathComponent("swift-project-eval-catalog.json")
        let catalog = try JSONDecoder().decode(
            Catalog.self,
            from: Data(contentsOf: catalogURL)
        )

        XCTAssertEqual(catalog.schemaVersion, 1)
        XCTAssertEqual(catalog.suite, "swift-project-desktop")
        XCTAssertGreaterThanOrEqual(catalog.sharedRequirements.count, 6)

        let expectedIDs = (1 ... 10).map { String(format: "SWIFT-%03d", $0) }
        XCTAssertEqual(catalog.tasks.map(\.id), expectedIDs)
        XCTAssertEqual(Set(catalog.tasks.map(\.id)).count, catalog.tasks.count)

        for task in catalog.tasks {
            XCTAssertFalse(task.platforms.isEmpty, task.id)
            XCTAssertFalse(task.title.isEmpty, task.id)
            XCTAssertGreaterThan(task.prompt.count, 80, task.id)
            XCTAssertFalse(task.fixture.isEmpty, task.id)
            XCTAssertFalse(task.commands.isEmpty, task.id)
            XCTAssertGreaterThanOrEqual(task.assertions.count, 4, task.id)
            XCTAssertTrue(
                task.prompt.localizedCaseInsensitiveContains("run") ||
                    task.prompt.localizedCaseInsensitiveContains("execute"),
                "\(task.id) must ask Quill Cowork to perform verifiable work"
            )
        }
    }

    func testReadableSwiftEvalPlanCoversEveryCatalogTask() throws {
        let planURL = Self.packageRoot()
            .appendingPathComponent("docs")
            .appendingPathComponent("SWIFT_PROJECT_EVALS.md")
        let plan = try String(contentsOf: planURL, encoding: .utf8)

        for number in 1 ... 10 {
            XCTAssertTrue(
                plan.contains(String(format: "SWIFT-%03d", number)),
                "Readable plan is missing SWIFT-\(String(format: "%03d", number))"
            )
        }
        Self.assertSource(plan, containsAll: [
            "visible desktop",
            "Open Project",
            "returned launch PID alone does not prove",
            ".xcresult",
            "simulator screenshot"
        ])
    }
}

private extension ParitySwiftProjectEvalCatalogGateTests {
    struct Catalog: Decodable {
        var schemaVersion: Int
        var suite: String
        var sharedRequirements: [String]
        var tasks: [Task]
    }

    struct Task: Decodable {
        var id: String
        var platforms: [String]
        var title: String
        var prompt: String
        var fixture: String
        var commands: [String]
        var assertions: [String]
    }
}

