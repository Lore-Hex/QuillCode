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

    func testSubagentCommandParsesAfterDependencies() {
        XCTAssertEqual(
            SlashCommandParser.parse("/subagents ship release | Builder: compile app | Verifier after Builder: run focused tests"),
            .subagents(.init(
                objective: "ship release",
                workers: [
                    .init(name: "Builder", role: "compile app"),
                    .init(name: "Verifier", role: "run focused tests", dependsOn: ["Builder"])
                ]
            ))
        )
    }

    func testSubagentCommandParsesMultipleCommaSeparatedDependencies() {
        XCTAssertEqual(
            SlashCommandParser.parse("/subagents ship | Builder: compile | Linter: lint | Release after Builder, Linter: publish"),
            .subagents(.init(
                objective: "ship",
                workers: [
                    .init(name: "Builder", role: "compile"),
                    .init(name: "Linter", role: "lint"),
                    .init(name: "Release", role: "publish", dependsOn: ["Builder", "Linter"])
                ]
            ))
        )
    }

    func testSubagentCommandKeepsNamesContainingAfterSubstringIntact() {
        XCTAssertEqual(
            SlashCommandParser.parse("/subagents draft | Drafter: write the draft"),
            .subagents(.init(
                objective: "draft",
                workers: [
                    .init(name: "Drafter", role: "write the draft")
                ]
            ))
        )
    }

    func testSubagentCommandParsesLeadingConcurrencyToken() {
        XCTAssertEqual(
            SlashCommandParser.parse("/subagents x2 ship release | Builder: compile | Linter: lint"),
            .subagents(.init(
                objective: "ship release",
                workers: [
                    .init(name: "Builder", role: "compile"),
                    .init(name: "Linter", role: "lint")
                ],
                maxConcurrentWorkers: 2
            ))
        )
    }

    func testSubagentCommandClampsConcurrencyTokenToWorkerLimit() {
        XCTAssertEqual(
            SlashCommandParser.parse("/subagents X9 audit | Sec: inspect"),
            .subagents(.init(
                objective: "audit",
                workers: [.init(name: "Sec", role: "inspect")],
                maxConcurrentWorkers: 6
            ))
        )
    }

    func testSubagentCommandIgnoresConcurrencyTokenForOrdinaryObjectives() {
        XCTAssertEqual(
            SlashCommandParser.parse("/subagents xerox audit | Sec: inspect"),
            .subagents(.init(
                objective: "xerox audit",
                workers: [.init(name: "Sec", role: "inspect")]
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
