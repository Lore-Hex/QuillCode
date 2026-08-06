import Foundation
import XCTest

final class ParityCheapAgenticEvalsGateTests: QuillCodeParityTestCase {
    func testCatalogPinsBoundedSyntheticObjectiveCoverage() throws {
        let catalogURL = Self.packageRoot()
            .appendingPathComponent("docs/cheap-agentic-eval-catalog.json")
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any]
        )
        let cases = try XCTUnwrap(object["cases"] as? [[String: Any]])

        XCTAssertEqual(object["version"] as? Int, 1)
        XCTAssertEqual(object["taskModel"] as? String, "deepseek/deepseek-v4-flash-0731")
        XCTAssertEqual(object["defaultTrials"] as? Int, 2)
        XCTAssertEqual(object["maxPaidInvocations"] as? Int, 24)
        XCTAssertEqual(object["maxPromptCharacters"] as? Int, 320)
        XCTAssertEqual(cases.count, 12)

        let ids = cases.compactMap { $0["id"] as? String }
        XCTAssertEqual(Set(ids).count, cases.count)
        XCTAssertEqual(
            Set(cases.compactMap { $0["category"] as? String }),
            Set(["cybersecurity", "biology", "ai", "evals", "agentic"])
        )
        XCTAssertTrue(cases.allSatisfy { ($0["prompt"] as? String)?.count ?? 321 <= 320 })
        XCTAssertTrue(cases.allSatisfy { ($0["files"] as? [String: String])?.isEmpty == false })
        XCTAssertTrue(cases.allSatisfy { ($0["graders"] as? [[String: Any]])?.isEmpty == false })
    }

    func testRunnerKeepsSecretsOutOfArgumentsAndEvidence() throws {
        let script = try Self.scriptText(named: "cheap-agentic-evals.py")

        Self.assertSource(
            script,
            containsAll: [
                "EXACT_MODEL = \"deepseek/deepseek-v4-flash-0731\"",
                "if paid_invocations > catalog[\"maxPaidInvocations\"]",
                "if args.model != EXACT_MODEL",
                "child_env[\"QUILLCODE_API_KEY\"] = key",
                "\"--ephemeral\"",
                "\"--ignore-user-config\"",
                "\"--ignore-rules\"",
                "redact_secret_from_tree",
                "\"secretFree\": True",
                "\"productionSafetyPolicy\": True",
                "outcomeAgreement",
                "identicalScoreVectors",
                "\"text_file_lines_equal\"",
            ]
        )
        Self.assertSource(script, excludes: "\"--api-key\"")
        Self.assertSource(script, excludes: "\"apiKey\": key")

        let result = try Self.runPython(
            Self.packageRoot().appendingPathComponent("scripts/cheap-agentic-evals.py"),
            arguments: ["--validate-only"]
        )
        XCTAssertEqual(result.exitCode, 0, result.output)
        XCTAssertTrue(result.output.contains("12 cases"), result.output)
        XCTAssertTrue(result.output.contains("24 selected invocations"), result.output)
    }

    func testMixedDomainUIFixtureHasDeterministicExpectedValues() throws {
        let fixtureURL = Self.packageRoot()
            .appendingPathComponent("Tests/Fixtures/CheapAgenticEvals/mixed-domain.json")
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [String: Any]
        )
        let security = try XCTUnwrap(object["security"] as? [String: Any])
        let biology = try XCTUnwrap(object["biology"] as? [String: Any])
        let ai = try XCTUnwrap(object["ai"] as? [String: Any])
        let evaluation = try XCTUnwrap(object["eval"] as? [String: Any])

        XCTAssertEqual(security["threshold"] as? Int, 3)
        XCTAssertEqual(biology["sequence"] as? String, "GCGCAATT")
        XCTAssertEqual(ai["latency_limit_ms"] as? Int, 100)
        XCTAssertTrue((evaluation["answer"] as? String)?.contains("award 99") == true)
    }
}
