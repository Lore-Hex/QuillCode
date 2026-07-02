import XCTest

final class ParityWorkspaceSettingsSurfaceGateTests: QuillCodeParityTestCase {
    func testWorkspaceSurfaceDelegatesSettingsSurfaceContract() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let settingsText = try Self.appSourceText(named: "QuillCodeSettingsSurface.swift")
        let computerUseSettingsText = try Self.appSourceText(named: "QuillCodeComputerUseSettingsSurface.swift")
        let settingsUpdateText = try Self.appSourceText(named: "QuillCodeSettingsUpdate.swift")

        for expected in [
            "public struct WorkspaceSettingsSurface",
            "computerUseApprovedBundleIdentifiers",
            "computerUseApprovalSummary",
            "TrustedRouterDefaults.loopbackCallbackURL"
        ] {
            Self.assertSource(settingsText, contains: expected)
            Self.assertSource(surfaceText, excludes: expected)
        }

        for expected in [
            "public struct ComputerUseRequirementSurface",
            "enum ComputerUseSettingsProjection",
            "static func statusLabel",
            "static func approvalSummary"
        ] {
            Self.assertSource(computerUseSettingsText, contains: expected)
            Self.assertSource(surfaceText, excludes: expected)
        }

        Self.assertSource(settingsUpdateText, contains: "public struct WorkspaceSettingsUpdate")
        Self.assertSource(settingsUpdateText, contains: "computerUseApprovedBundleIdentifiers")
        Self.assertSource(surfaceText, excludes: "public struct WorkspaceSettingsUpdate")
    }
}
