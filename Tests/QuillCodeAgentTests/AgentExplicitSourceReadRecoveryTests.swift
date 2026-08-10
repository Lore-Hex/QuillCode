import XCTest
import QuillCodeCore
@testable import QuillCodeAgent

final class AgentExplicitSourceReadRecoveryTests: XCTestCase {
    private func makeWorkspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("explicit-read-recovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("inputs"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("outputs"),
            withIntermediateDirectories: true
        )
        try "context".write(
            to: root.appendingPathComponent("inputs/context.md"),
            atomically: true,
            encoding: .utf8
        )
        try "name,value\nalpha,1\n".write(
            to: root.appendingPathComponent("inputs/data.csv"),
            atomically: true,
            encoding: .utf8
        )
        try "old output".write(
            to: root.appendingPathComponent("outputs/report.md"),
            atomically: true,
            encoding: .utf8
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    func testAdvancesOnlyUnreadExplicitSourceFilesInOrder() throws {
        let root = try makeWorkspace()
        let prompt = """
        Use the file read tool separately on `inputs/context.md` and `inputs/data.csv`.
        Write the deliverable to `outputs/report.md`.
        """

        let first = AgentExplicitSourceReadRecovery.nextAction(
            userMessage: prompt,
            workspaceRoot: root,
            tools: [ToolDefinition.fileRead],
            successfullyReadPaths: []
        )
        guard case .tool(let firstCall)? = first else {
            return XCTFail("expected the first explicit source read")
        }
        XCTAssertEqual(firstCall.name, ToolDefinition.fileRead.name)
        XCTAssertEqual(firstCall.argumentsJSON, ToolArguments.json(["path": "inputs/context.md"]))

        let second = AgentExplicitSourceReadRecovery.nextAction(
            userMessage: prompt,
            workspaceRoot: root,
            tools: [ToolDefinition.fileRead],
            successfullyReadPaths: ["./inputs/context.md"]
        )
        guard case .tool(let secondCall)? = second else {
            return XCTFail("expected the second explicit source read")
        }
        XCTAssertEqual(secondCall.name, ToolDefinition.fileRead.name)
        XCTAssertEqual(secondCall.argumentsJSON, ToolArguments.json(["path": "inputs/data.csv"]))

        XCTAssertNil(AgentExplicitSourceReadRecovery.nextAction(
            userMessage: prompt,
            workspaceRoot: root,
            tools: [ToolDefinition.fileRead],
            successfullyReadPaths: ["inputs/context.md", "inputs/data.csv"]
        ))
    }

    func testRejectsNegatedMissingUnsafeAndDeliverablePaths() throws {
        let root = try makeWorkspace()
        let prompt = """
        Do not use the file read tool on `inputs/context.md`.
        Use the file read tool on `../secret.md`, `inputs/missing.md`, and `outputs/report.md`.
        Write the deliverable to `outputs/report.md`.
        """

        XCTAssertNil(AgentExplicitSourceReadRecovery.nextAction(
            userMessage: prompt,
            workspaceRoot: root,
            tools: [ToolDefinition.fileRead],
            successfullyReadPaths: []
        ))
    }

    func testAdvancesExistingFilesFromAffirmativeRequiredInputInventory() throws {
        let root = try makeWorkspace()
        let prompt = """
        All local files for this task are mapped in `inputs/source-map.md`.
        Read every applicable source directly before acting.
        For this task the required inputs are: `inputs/context.md`, `inputs`, `inputs/data.csv`.
        Write the deliverable to `outputs/report.md`.
        """

        let first = AgentExplicitSourceReadRecovery.nextAction(
            userMessage: prompt,
            workspaceRoot: root,
            tools: [ToolDefinition.fileRead],
            successfullyReadPaths: []
        )
        guard case .tool(let firstCall)? = first else {
            return XCTFail("expected the first required regular file")
        }
        XCTAssertEqual(firstCall.argumentsJSON, ToolArguments.json(["path": "inputs/context.md"]))

        let second = AgentExplicitSourceReadRecovery.nextAction(
            userMessage: prompt,
            workspaceRoot: root,
            tools: [ToolDefinition.fileRead],
            successfullyReadPaths: ["inputs/context.md"]
        )
        guard case .tool(let secondCall)? = second else {
            return XCTFail("expected the required file after skipping the directory")
        }
        XCTAssertEqual(secondCall.argumentsJSON, ToolArguments.json(["path": "inputs/data.csv"]))
    }

    func testExtractsOnlySafeNondeliverableRequiredInputPaths() {
        let prompt = """
        Read every applicable source directly before acting.
        For this task the required inputs are: `inputs/context.md`, `../secret.md`, \
        `inputs/data.csv`, `outputs/report.md`, `inputs/data.csv`.
        Save the complete result to `outputs/report.md`.
        """

        XCTAssertEqual(
            AgentExplicitSourceReadRecovery.requiredInputPaths(in: prompt),
            ["inputs/context.md", "inputs/data.csv"]
        )
    }
}
