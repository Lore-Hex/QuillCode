import XCTest

final class ParityWorkspaceRuntimeFactoryGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelTestsDoNotOwnRuntimeFactoryCoverage() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let runtimeFactoryTests = try Self.appTestSourceText(named: "WorkspaceRuntimeFactoryTests.swift")

        Self.assertSource(runtimeFactoryTests, containsAll: [
            "QuillCodeRuntimeFactory(",
            "fetchModelCatalog",
            "QUILLCODE_USE_MOCK_LLM"
        ])
        Self.assertSource(modelTests, excludesAll: [
            "QuillCodeRuntimeFactory(",
            "func testRuntimeFactory"
        ])
    }
}
