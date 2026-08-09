import XCTest

final class ParityWorkspaceSettingsPersistenceGateTests: QuillCodeParityTestCase {
    func testDesktopSettingsUseCompensatedContentFreePersistence() throws {
        let bootstrapText = try Self.appSourceText(named: "WorkspaceBootstrap.swift")
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let persistenceText = try Self.appSourceText(named: "WorkspaceSettingsPersistence.swift")
        let issueText = try Self.appSourceText(named: "WorkspaceSettingsPersistenceIssue.swift")
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let coordinatorText = try Self.desktopSourceText(
            named: "QuillCodeDesktopSettingsCoordinator.swift"
        )
        let signInText = try Self.desktopSourceText(named: "QuillCodeDesktopSignInCoordinator.swift")

        Self.assertSource(persistenceText, containsAll: [
            "struct WorkspaceSettingsPersistenceTransaction",
            "private func restoreCredential(",
            "public struct WorkspaceSettingsPersistenceError",
            "failedKinds: Set<WorkspaceSettingsPersistenceKind>",
            "rollbackFailed: Bool"
        ])
        Self.assertSource(issueText, containsAll: [
            "final class WorkspaceSettingsPersistenceIssueTracker",
            "private var failedKinds: Set<WorkspaceSettingsPersistenceKind>",
            "Private content included"
        ])
        Self.assertSource(bootstrapText, contains: "public func saveSettingsTransaction(")
        Self.assertSource(modelText, contains: "let settingsPersistenceIssueTracker")
        Self.assertSource(
            surfaceText,
            contains: "settingsPersistenceIssueTracker.runtimeIssue"
        )
        Self.assertSource(coordinatorText, containsAll: [
            "bootstrap.saveSettingsTransaction(",
            "model.recordSettingsPersistenceFailure(",
            "model.recordSettingsPersistenceSuccess("
        ])
        Self.assertSource(coordinatorText, excludesAll: [
            "try? bootstrap.saveConfig",
            "try? bootstrap.clearTrustedRouterAPIKey",
            "try? bootstrap.saveTrustedRouterAPIKey"
        ])
        Self.assertSource(signInText, containsAll: [
            "bootstrap.saveSettingsTransaction(",
            "catch let error as WorkspaceSettingsPersistenceError"
        ])
        Self.assertSource(signInText, excludesAll: [
            "try bootstrap.saveTrustedRouterAPIKey(token.key)",
            "try bootstrap.saveConfig(config)"
        ])
    }
}
