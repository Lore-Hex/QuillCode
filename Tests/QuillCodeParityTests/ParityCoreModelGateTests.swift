import XCTest

final class ParityCoreModelGateTests: QuillCodeParityTestCase {
    func testCoreToolModelsLiveOutsideGeneralDomainModels() throws {
        Self.assertLegacyGeneralModelsFileIsRetired()
        let modelsText = try Self.generalDomainModelsText()
        let definitionText = try Self.coreSourceText(named: "ToolDefinition.swift")
        let callText = try Self.coreSourceText(named: "ToolCall.swift")
        let resultText = try Self.coreSourceText(named: "ToolResult.swift")
        let browserOutputText = try Self.coreSourceText(named: "BrowserInspectionToolOutput.swift")
        let memoryOutputText = try Self.coreSourceText(named: "MemoryRememberToolOutput.swift")
        let definitionsText = try Self.coreSourceText(named: "CoreToolDefinitions.swift")

        XCTAssertTrue(definitionText.contains("public struct ToolDefinition"), "Tool schema records should live in a focused core file.")
        XCTAssertTrue(callText.contains("public struct ToolCall"), "Tool-call payload records should live in a focused core file.")
        XCTAssertTrue(resultText.contains("public struct ToolResult"), "Tool-result payload records should live in a focused core file.")
        XCTAssertTrue(callText.contains("redactedForTranscript"), "Tool-call redaction belongs with tool-call payload records.")
        XCTAssertTrue(browserOutputText.contains("public struct BrowserInspectionToolOutput"), "Browser output compatibility belongs in its own focused core file.")
        XCTAssertTrue(memoryOutputText.contains("public struct MemoryRememberToolOutput"), "Memory output compatibility belongs in its own focused core file.")
        XCTAssertTrue(definitionsText.contains("static let planUpdate"), "Built-in core tool definitions should live in a focused catalog.")
        XCTAssertTrue(definitionsText.contains("static let handoffUpdate"), "Built-in handoff tool schema should live in the focused catalog.")
        XCTAssertTrue(definitionsText.contains("static let browserOpen"), "Browser tool schema should live in the focused catalog.")
        XCTAssertFalse(modelsText.contains("public struct ToolDefinition"), "General domain models should not own tool schema records.")
        XCTAssertFalse(modelsText.contains("public struct ToolCall"), "General domain models should not own tool-call payload records.")
        XCTAssertFalse(modelsText.contains("public struct ToolResult"), "General domain models should not own tool-result payload records.")
        XCTAssertFalse(modelsText.contains("redactedForTranscript"), "General domain models should not own tool-call redaction.")
        XCTAssertFalse(modelsText.contains("public struct BrowserInspectionToolOutput"), "General domain models should not own tool-specific output compatibility.")
        XCTAssertFalse(modelsText.contains("public struct MemoryRememberToolOutput"), "General domain models should not own tool-specific output compatibility.")
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: Self.packageRoot()
                    .appendingPathComponent("Sources/QuillCodeCore/ToolModels.swift")
                    .path
            ),
            "ToolModels.swift should not be reintroduced as a broad catch-all."
        )
    }

    func testProjectModelsLiveOutsideGeneralDomainModels() throws {
        Self.assertLegacyGeneralModelsFileIsRetired()
        let modelsText = try Self.generalDomainModelsText()
        let connectionText = try Self.coreSourceText(named: "ProjectConnection.swift")
        let projectRefText = try Self.coreSourceText(named: "ProjectRef.swift")
        let instructionText = try Self.coreSourceText(named: "ProjectInstruction.swift")
        let localActionText = try Self.coreSourceText(named: "LocalEnvironmentAction.swift")
        let extensionText = try Self.coreSourceText(named: "ProjectExtensionManifest.swift")

        XCTAssertTrue(connectionText.contains("public enum ProjectConnectionKind"), "Project connection kinds should live with connection records.")
        XCTAssertTrue(connectionText.contains("public struct ProjectConnection"), "Project connection parsing and display should live in a focused core file.")
        XCTAssertTrue(connectionText.contains("parseSSH"), "SSH project parsing should stay with project connection records.")
        XCTAssertTrue(projectRefText.contains("public struct ProjectRef"), "Project references should live in a focused project ref file.")
        XCTAssertTrue(instructionText.contains("public struct ProjectInstruction"), "Project instructions should live in a focused instruction model file.")
        XCTAssertTrue(localActionText.contains("public struct LocalEnvironmentAction"), "Local environment actions should live in their own focused model file.")
        XCTAssertTrue(extensionText.contains("public struct ProjectExtensionManifest"), "Project extension manifests should live in their own focused model file.")
        XCTAssertFalse(modelsText.contains("public enum ProjectConnectionKind"), "General domain models should not own project connection kinds.")
        XCTAssertFalse(modelsText.contains("public struct ProjectConnection"), "General domain models should not own project connection records.")
        XCTAssertFalse(modelsText.contains("parseSSH"), "General domain models should not own SSH project parsing.")
        XCTAssertFalse(modelsText.contains("public struct ProjectRef"), "General domain models should not own project references.")
        XCTAssertFalse(modelsText.contains("public struct LocalEnvironmentAction"), "General domain models should not own local environment actions.")
        XCTAssertFalse(modelsText.contains("public struct ProjectExtensionManifest"), "General domain models should not own project extension manifests.")
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: Self.packageRoot()
                    .appendingPathComponent("Sources/QuillCodeCore/ProjectModels.swift")
                    .path
            ),
            "ProjectModels.swift should not be reintroduced as a broad catch-all."
        )
    }
}
