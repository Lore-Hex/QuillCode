import XCTest

final class ParityCoreModelGateTests: QuillCodeParityTestCase {
    func testCoreToolModelsLiveOutsideGeneralDomainModels() throws {
        let modelsText = try Self.coreSourceText(named: "Models.swift")
        let toolModelsText = try Self.coreSourceText(named: "ToolModels.swift")

        XCTAssertTrue(toolModelsText.contains("public struct ToolDefinition"), "Tool schema records should live in a focused core file.")
        XCTAssertTrue(toolModelsText.contains("public struct ToolCall"), "Tool-call payload records should live beside tool schemas.")
        XCTAssertTrue(toolModelsText.contains("public struct ToolResult"), "Tool-result payload records should live beside tool schemas.")
        XCTAssertTrue(toolModelsText.contains("redactedForTranscript"), "Tool-call redaction belongs with tool-call payload records.")
        XCTAssertTrue(toolModelsText.contains("public struct BrowserInspectionToolOutput"), "Tool-specific browser output compatibility belongs with tool models.")
        XCTAssertTrue(toolModelsText.contains("public struct MemoryRememberToolOutput"), "Tool-specific memory output compatibility belongs with tool models.")
        XCTAssertTrue(toolModelsText.contains("static let planUpdate"), "Built-in core tool definitions should live with tool schema records.")
        XCTAssertFalse(modelsText.contains("public struct ToolDefinition"), "General domain models should not own tool schema records.")
        XCTAssertFalse(modelsText.contains("public struct ToolCall"), "General domain models should not own tool-call payload records.")
        XCTAssertFalse(modelsText.contains("public struct ToolResult"), "General domain models should not own tool-result payload records.")
        XCTAssertFalse(modelsText.contains("redactedForTranscript"), "General domain models should not own tool-call redaction.")
        XCTAssertFalse(modelsText.contains("public struct BrowserInspectionToolOutput"), "General domain models should not own tool-specific output compatibility.")
        XCTAssertFalse(modelsText.contains("public struct MemoryRememberToolOutput"), "General domain models should not own tool-specific output compatibility.")
    }

    func testProjectModelsLiveOutsideGeneralDomainModels() throws {
        let modelsText = try Self.coreSourceText(named: "Models.swift")
        let projectText = try Self.coreSourceText(named: "ProjectModels.swift")

        XCTAssertTrue(projectText.contains("public enum ProjectConnectionKind"), "Project connection kinds should live in a focused core file.")
        XCTAssertTrue(projectText.contains("public struct ProjectConnection"), "Project connection parsing and display should live beside project records.")
        XCTAssertTrue(projectText.contains("parseSSH"), "SSH project parsing should stay with project connection records.")
        XCTAssertTrue(projectText.contains("public struct ProjectRef"), "Project references should live in the project model boundary.")
        XCTAssertTrue(projectText.contains("public struct LocalEnvironmentAction"), "Local environment actions should live beside project records.")
        XCTAssertTrue(projectText.contains("public struct ProjectExtensionManifest"), "Project extension manifests should live beside project records.")
        XCTAssertFalse(modelsText.contains("public enum ProjectConnectionKind"), "General domain models should not own project connection kinds.")
        XCTAssertFalse(modelsText.contains("public struct ProjectConnection"), "General domain models should not own project connection records.")
        XCTAssertFalse(modelsText.contains("parseSSH"), "General domain models should not own SSH project parsing.")
        XCTAssertFalse(modelsText.contains("public struct ProjectRef"), "General domain models should not own project references.")
        XCTAssertFalse(modelsText.contains("public struct LocalEnvironmentAction"), "General domain models should not own local environment actions.")
        XCTAssertFalse(modelsText.contains("public struct ProjectExtensionManifest"), "General domain models should not own project extension manifests.")
    }
}
