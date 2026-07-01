import XCTest

final class ParityWorkspaceExecutionContextSurfaceGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesExecutionContextSurfaceBuilding() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let contextText = try Self.appSourceText(named: "WorkspaceModelContext.swift")
        let builderText = try Self.appSourceText(
            named: "WorkspaceExecutionContextSurfaceBuilder.swift"
        )

        Self.assertSource(contextText, containsAll: [
            "extension QuillCodeWorkspaceModel",
            "public var selectedThread",
            "public var selectedProject",
            "public var activeWorkspaceRoot",
            "var terminalCurrentDirectoryURL",
            "public var currentToolCards",
            "public var currentTimelineItems",
            "WorkspaceExecutionContextSurfaceBuilder("
        ])
        Self.assertSource(builderText, containsAll: [
            "struct WorkspaceExecutionContextSurfaceBuilder",
            "func enrichToolCards(",
            "func enrichTimelineItems(",
            "static func isProjectExecutionTool"
        ])
        Self.assertSource(modelText, excludesAll: [
            "public var selectedThread",
            "public var selectedProject",
            "public var activeWorkspaceRoot",
            "public var currentToolCards",
            "public var currentTimelineItems",
            "WorkspaceExecutionContextSurfaceBuilder(",
            "private func enrichToolCards",
            "private func enrichTimelineItems",
            "private static func isProjectExecutionTool"
        ])
    }
}
