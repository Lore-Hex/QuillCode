import XCTest
@testable import QuillCodeApp

final class SlashSubagentCommandParserTests: XCTestCase {
    func testSubagentAliasesAreSupported() {
        XCTAssertTrue(SlashSubagentCommandParser.supports("subagent"))
        XCTAssertTrue(SlashSubagentCommandParser.supports("subagents"))
        XCTAssertTrue(SlashSubagentCommandParser.supports("parallel"))
        XCTAssertTrue(SlashSubagentCommandParser.supports("agents"))
        XCTAssertFalse(SlashSubagentCommandParser.supports("agent"))
    }

    func testSubagentCommandParsesObjectiveAndNamedWorkers() {
        XCTAssertEqual(
            SlashCommandParser.parse("/subagents audit auth | Security: inspect auth flow | Tests: run focused tests"),
            .subagents(.init(
                objective: "audit auth",
                workers: [
                    .init(name: "Security", role: "inspect auth flow"),
                    .init(name: "Tests", role: "run focused tests")
                ]
            ))
        )
    }

    func testSubagentCommandDefaultsWorkerNamesForUnnamedRoles() {
        XCTAssertEqual(
            SlashCommandParser.parse("/parallel validate release | inspect docs | run smoke"),
            .subagents(.init(
                objective: "validate release",
                workers: [
                    .init(name: "Worker 1", role: "inspect docs"),
                    .init(name: "Worker 2", role: "run smoke")
                ]
            ))
        )
    }

    func testSubagentCommandRejectsMissingWorkers() {
        XCTAssertEqual(
            SlashCommandParser.parse("/subagents validate release"),
            .invalid("Add at least one subagent after `|`, for example /subagents audit auth | Security: inspect auth flow.")
        )
        XCTAssertEqual(
            SlashCommandParser.parse("/subagents"),
            .invalid("Usage: /subagents objective | Name: worker role | Verifier: worker role.")
        )
    }
}
