import XCTest

final class ParityWorkspaceContextToolGateTests: QuillCodeParityTestCase {
    func testWorkspaceSurfaceDelegatesContextBannerBuilding() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let builderText = try Self.appSourceText(named: "WorkspaceContextBannerBuilder.swift")

        Self.assertSource(builderText, contains: "struct WorkspaceContextBannerBuilder")
        Self.assertSource(builderText, contains: "func banner() -> ContextBannerSurface?")
        Self.assertSource(builderText, contains: "estimatedContextTokens")
        Self.assertSource(surfaceText, contains: "WorkspaceContextBannerBuilder(")
        Self.assertSource(surfaceText, excludes: "private func contextBanner(")
        Self.assertSource(surfaceText, excludes: "contextUsedPercent")
        Self.assertSource(surfaceText, excludes: "estimatedContextTokens")
    }

}
