import Foundation
import XCTest

final class ParityBenchmarkCompatibilityEvalsTests: QuillCodeParityTestCase {
    func testCatalogsPinCurrentUpstreamsAndExactTaskModel() throws {
        let root = Self.packageRoot()
        let tau = try catalog(named: "tau3-banking-eval-catalog.json", root: root)
        let bfcl = try catalog(named: "bfcl-eval-catalog.json", root: root)
        let tauCases = try XCTUnwrap(tau["cases"] as? [[String: Any]])
        let bfclCases = try XCTUnwrap(bfcl["cases"] as? [[String: Any]])
        let tauUpstream = try XCTUnwrap(tau["upstream"] as? [String: Any])
        let bfclUpstream = try XCTUnwrap(bfcl["upstream"] as? [String: Any])

        XCTAssertEqual(tau["suite"] as? String, "tau3-banking")
        XCTAssertEqual(bfcl["suite"] as? String, "bfcl")
        XCTAssertEqual(tau["taskModel"] as? String, "deepseek/deepseek-v4-flash-0731")
        XCTAssertEqual(bfcl["taskModel"] as? String, "deepseek/deepseek-v4-flash-0731")
        XCTAssertEqual(tau["maxPaidInvocations"] as? Int, 24)
        XCTAssertEqual(bfcl["maxPaidInvocations"] as? Int, 24)
        XCTAssertEqual(tauCases.count, 6)
        XCTAssertEqual(bfclCases.count, 8)
        XCTAssertEqual(tauUpstream["release"] as? String, "v1.0.1")
        XCTAssertEqual(tauUpstream["domain"] as? String, "banking_knowledge")
        XCTAssertEqual(bfclUpstream["evaluatorPackage"] as? String, "bfcl-eval==2025.12.17")
        XCTAssertEqual(bfclUpstream["generation"] as? String, "BFCL V4")
    }

    func testRunnerValidatesAndExecutesAllOfflineFixtures() throws {
        let script = Self.packageRoot().appendingPathComponent("scripts/benchmark-compat-evals.py")
        let source = try String(contentsOf: script, encoding: .utf8)
        Self.assertSource(
            source,
            containsAll: [
                "EXACT_MODEL = \"deepseek/deepseek-v4-flash-0731\"",
                "BASE_URL = \"https://api.trustedrouter.com/v1\"",
                "response_format",
                "InvocationBudget",
                "execute_banking_tool",
                "calls_match",
                "redact_secret_from_tree",
                "\"officialBenchmarkScore\": False",
                "\"secretFree\": True",
            ]
        )
        Self.assertSource(source, excludes: "--api-key")

        let validation = try Self.runPython(script, arguments: ["--validate-only"])
        XCTAssertEqual(validation.exitCode, 0, validation.output)
        XCTAssertTrue(validation.output.contains("6 tau3-banking cases"), validation.output)
        XCTAssertTrue(validation.output.contains("8 bfcl cases"), validation.output)
        XCTAssertTrue(validation.output.contains("paid-invocation fuse 24"), validation.output)

        let selfTest = try Self.runPython(script, arguments: ["--self-test"])
        XCTAssertEqual(selfTest.exitCode, 0, selfTest.output)
        XCTAssertTrue(selfTest.output.contains("14/14 compatibility fixtures"), selfTest.output)
    }

    private func catalog(named name: String, root: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: root.appendingPathComponent("docs").appendingPathComponent(name))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
