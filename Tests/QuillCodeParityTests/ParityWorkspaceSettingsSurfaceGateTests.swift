import XCTest

final class ParityWorkspaceSettingsSurfaceGateTests: QuillCodeParityTestCase {
    func testWorkspaceSurfaceDelegatesSettingsSurfaceContract() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let settingsText = try Self.appSourceText(named: "QuillCodeSettingsSurface.swift")

        for expected in [
            "public struct WorkspaceSettingsSurface",
            "public struct WorkspaceSettingsUpdate",
            "public struct ComputerUseRequirementSurface",
            "private static func computerUseStatusLabel",
            "TrustedRouterDefaults.loopbackCallbackURL"
        ] {
            Self.assertSource(settingsText, contains: expected)
            Self.assertSource(surfaceText, excludes: expected)
        }
    }
}
