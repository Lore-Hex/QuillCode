import XCTest
import QuillCodeApp
import QuillCodeCore
import QuillCodePersistence
@testable import quill_code_desktop

@MainActor
final class QuillCodeDesktopSettingsPersistenceTests: XCTestCase {
    func testQuickSpendLimitPersistsWithoutChangingOtherConfiguration() throws {
        let root = try makeTempDirectory()
        let paths = QuillCodePaths(home: root)
        let bootstrap = makeBootstrap(paths: paths)
        let original = AppConfig(defaultModel: "acme/specialist", runSpendFuseUSD: 1)
        try bootstrap.saveConfig(original)
        let model = try bootstrap.makeModel()
        let coordinator = QuillCodeDesktopSettingsCoordinator(bootstrap: bootstrap)

        coordinator.setRunSpendFuseUSD(2, on: model)

        let persisted = try ConfigStore(fileURL: paths.configFile).load()
        XCTAssertEqual(model.root.config.runSpendFuseUSD, 2)
        XCTAssertEqual(persisted.runSpendFuseUSD, 2)
        XCTAssertEqual(persisted.defaultModel, original.defaultModel)
    }

    func testQuickSpendLimitRollsBackWhenPersistenceFails() throws {
        let root = try makeTempDirectory()
        let paths = QuillCodePaths(home: root)
        let bootstrap = makeBootstrap(paths: paths)
        try bootstrap.saveConfig(AppConfig(runSpendFuseUSD: 1))
        let model = try bootstrap.makeModel()
        let coordinator = QuillCodeDesktopSettingsCoordinator(bootstrap: bootstrap)
        try replaceConfigFileWithDirectory(paths.configFile)

        coordinator.setRunSpendFuseUSD(2, on: model)

        XCTAssertEqual(model.root.config.runSpendFuseUSD, 1)
        XCTAssertEqual(model.surface().runtimeIssue?.title, "A settings change is not saved")
    }

    func testQuickConfigurationFailureRemainsVisibleUntilFullSnapshotSucceeds() throws {
        let root = try makeTempDirectory()
        let paths = QuillCodePaths(home: root)
        let bootstrap = makeBootstrap(paths: paths)
        try bootstrap.saveConfig(AppConfig())
        let model = try bootstrap.makeModel()
        let coordinator = QuillCodeDesktopSettingsCoordinator(bootstrap: bootstrap)
        try replaceConfigFileWithDirectory(paths.configFile)

        coordinator.setMode(.plan, on: model)

        let issue = try XCTUnwrap(model.surface().runtimeIssue)
        XCTAssertEqual(model.root.config.mode, .plan)
        XCTAssertEqual(issue.title, "A settings change is not saved")
        XCTAssertEqual(
            issue.diagnostics.first { $0.label == "Affected data" }?.value,
            "Configuration"
        )
        XCTAssertFalse(issue.message.contains(root.path))

        try FileManager.default.removeItem(at: paths.configFile)
        coordinator.setMode(.plan, on: model)

        XCTAssertNotEqual(model.surface().runtimeIssue?.title, issue.title)
        XCTAssertEqual(try ConfigStore(fileURL: paths.configFile).load().mode, .plan)
    }

    func testCredentialAndConfigurationFailureRollsBackThenRetriesAtomically() throws {
        let root = try makeTempDirectory()
        let paths = QuillCodePaths(home: root)
        let bootstrap = makeBootstrap(paths: paths)
        let currentConfig = AppConfig(apiBaseURL: "https://current.example")
        let priorCredential = "prior-private-credential"
        let replacementCredential = "replacement-private-credential"
        let privateAPIBaseURL = "https://private-acquisition.example"
        try bootstrap.saveConfig(currentConfig)
        try bootstrap.saveTrustedRouterAPIKey(priorCredential)
        let model = try bootstrap.makeModel()
        let coordinator = QuillCodeDesktopSettingsCoordinator(bootstrap: bootstrap)
        try replaceConfigFileWithDirectory(paths.configFile)
        let update = WorkspaceSettingsUpdate(
            apiBaseURL: privateAPIBaseURL,
            replacementAPIKey: replacementCredential
        )
        var refreshCount = 0

        coordinator.saveSettings(update, to: model) {
            refreshCount += 1
        }

        let issue = try XCTUnwrap(model.surface().runtimeIssue)
        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(model.root.config, currentConfig)
        XCTAssertEqual(try storedCredential(paths: paths), priorCredential)
        XCTAssertEqual(issue.title, "Some settings changes are not saved")
        XCTAssertEqual(
            issue.diagnostics.first { $0.label == "Affected data" }?.value,
            "Configuration, TrustedRouter credential"
        )
        let visibleText = ([issue.title, issue.message] + issue.diagnostics.flatMap {
            [$0.label, $0.value]
        }).joined(separator: " ")
        XCTAssertFalse(visibleText.contains(root.path))
        XCTAssertFalse(visibleText.contains(privateAPIBaseURL))
        XCTAssertFalse(visibleText.contains(priorCredential))
        XCTAssertFalse(visibleText.contains(replacementCredential))

        try FileManager.default.removeItem(at: paths.configFile)
        coordinator.saveSettings(update, to: model) {}

        XCTAssertEqual(model.root.config.apiBaseURL, privateAPIBaseURL)
        XCTAssertEqual(try storedCredential(paths: paths), replacementCredential)
        XCTAssertNotEqual(model.surface().runtimeIssue?.title, issue.title)
        XCTAssertEqual(
            try ConfigStore(fileURL: paths.configFile).load().apiBaseURL,
            privateAPIBaseURL
        )
    }

    private func makeBootstrap(paths: QuillCodePaths) -> QuillCodeWorkspaceBootstrap {
        QuillCodeWorkspaceBootstrap(
            paths: paths,
            runtimeFactory: QuillCodeRuntimeFactory(
                paths: paths,
                environment: ["QUILLCODE_USE_MOCK_LLM": "1"]
            )
        )
    }

    private func replaceConfigFileWithDirectory(_ fileURL: URL) throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: false)
    }

    private func storedCredential(paths: QuillCodePaths) throws -> String? {
        try FileSecretStore(directory: paths.secretsDirectory)
            .read(QuillSecretKeys.trustedRouterAPIKey)
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
