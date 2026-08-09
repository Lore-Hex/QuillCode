import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceSettingsPersistenceTransactionTests: XCTestCase {
    private enum StubError: Error {
        case failed
    }

    func testConfigurationOnlySaveDoesNotReadCredential() throws {
        var savedConfiguration: AppConfig?
        var credentialReadCount = 0
        let proposed = AppConfig(apiBaseURL: "https://settings.example")
        let transaction = WorkspaceSettingsPersistenceTransaction(
            saveConfiguration: { savedConfiguration = $0 },
            readCredential: {
                credentialReadCount += 1
                return nil
            },
            writeCredential: { _ in XCTFail("Credential must remain untouched") },
            clearCredential: { XCTFail("Credential must remain untouched") }
        )

        try transaction.apply(
            currentConfig: AppConfig(),
            proposedConfig: proposed,
            credentialMutation: .unchanged
        )

        XCTAssertEqual(savedConfiguration, proposed)
        XCTAssertEqual(credentialReadCount, 0)
    }

    func testPartialCredentialWriteIsCompensatedBeforeConfigurationSave() throws {
        let current = AppConfig(apiBaseURL: "https://current.example")
        let proposed = AppConfig(apiBaseURL: "https://private-proposed.example")
        let priorCredential = "prior-private-credential"
        let replacementCredential = "replacement-private-credential"
        var storedCredential: String? = priorCredential
        var credentialWriteCount = 0
        var configurationSaveCount = 0
        let transaction = WorkspaceSettingsPersistenceTransaction(
            saveConfiguration: { _ in configurationSaveCount += 1 },
            readCredential: { storedCredential },
            writeCredential: { credential in
                storedCredential = credential
                credentialWriteCount += 1
                if credentialWriteCount == 1 {
                    throw StubError.failed
                }
            },
            clearCredential: { storedCredential = nil }
        )

        let error = try persistenceError {
            try transaction.apply(
                currentConfig: current,
                proposedConfig: proposed,
                credentialMutation: .replace(replacementCredential)
            )
        }

        XCTAssertEqual(storedCredential, priorCredential)
        XCTAssertEqual(credentialWriteCount, 2)
        XCTAssertEqual(configurationSaveCount, 0)
        XCTAssertEqual(error.failedKinds, [.configuration, .trustedRouterCredential])
        XCTAssertFalse(error.rollbackFailed)
        assertContentFree(error, secrets: [priorCredential, replacementCredential, proposed.apiBaseURL])
    }

    func testConfigurationFailureRestoresPriorCredential() throws {
        let current = AppConfig(apiBaseURL: "https://current.example")
        let proposed = AppConfig(apiBaseURL: "https://private-proposed.example")
        let priorCredential = "prior-private-credential"
        let replacementCredential = "replacement-private-credential"
        var storedCredential: String? = priorCredential
        var configurationSaveCount = 0
        let transaction = WorkspaceSettingsPersistenceTransaction(
            saveConfiguration: { _ in
                configurationSaveCount += 1
                throw StubError.failed
            },
            readCredential: { storedCredential },
            writeCredential: { storedCredential = $0 },
            clearCredential: { storedCredential = nil }
        )

        let error = try persistenceError {
            try transaction.apply(
                currentConfig: current,
                proposedConfig: proposed,
                credentialMutation: .replace(replacementCredential)
            )
        }

        XCTAssertEqual(storedCredential, priorCredential)
        XCTAssertEqual(configurationSaveCount, 1)
        XCTAssertEqual(error.failedKinds, [.configuration, .trustedRouterCredential])
        XCTAssertFalse(error.rollbackFailed)
        assertContentFree(error, secrets: [priorCredential, replacementCredential, proposed.apiBaseURL])
    }

    func testRollbackFailureReportsOnlyBoundedCategories() throws {
        let current = AppConfig(apiBaseURL: "https://current.example")
        let proposed = AppConfig(apiBaseURL: "https://private-proposed.example")
        let priorCredential = "prior-private-credential"
        let replacementCredential = "replacement-private-credential"
        var storedCredential: String? = priorCredential
        var credentialWriteCount = 0
        let transaction = WorkspaceSettingsPersistenceTransaction(
            saveConfiguration: { _ in throw StubError.failed },
            readCredential: { storedCredential },
            writeCredential: { credential in
                credentialWriteCount += 1
                if credentialWriteCount > 1 {
                    throw StubError.failed
                }
                storedCredential = credential
            },
            clearCredential: { throw StubError.failed }
        )

        let error = try persistenceError {
            try transaction.apply(
                currentConfig: current,
                proposedConfig: proposed,
                credentialMutation: .replace(replacementCredential)
            )
        }

        XCTAssertEqual(storedCredential, replacementCredential)
        XCTAssertEqual(error.failedKinds, [.configuration, .trustedRouterCredential])
        XCTAssertTrue(error.rollbackFailed)
        assertContentFree(error, secrets: [priorCredential, replacementCredential, proposed.apiBaseURL])
    }

    func testCredentialReadFailureDoesNotAttemptAnyWrite() throws {
        var configurationSaveCount = 0
        var credentialWriteCount = 0
        let transaction = WorkspaceSettingsPersistenceTransaction(
            saveConfiguration: { _ in configurationSaveCount += 1 },
            readCredential: { throw StubError.failed },
            writeCredential: { _ in credentialWriteCount += 1 },
            clearCredential: { credentialWriteCount += 1 }
        )

        let error = try persistenceError {
            try transaction.apply(
                currentConfig: AppConfig(),
                proposedConfig: AppConfig(),
                credentialMutation: .clear
            )
        }

        XCTAssertEqual(configurationSaveCount, 0)
        XCTAssertEqual(credentialWriteCount, 0)
        XCTAssertEqual(error.failedKinds, [.trustedRouterCredential])
        XCTAssertFalse(error.rollbackFailed)
    }

    private func persistenceError(
        _ operation: () throws -> Void
    ) throws -> WorkspaceSettingsPersistenceError {
        do {
            try operation()
            XCTFail("Expected settings persistence to fail")
            throw StubError.failed
        } catch let error as WorkspaceSettingsPersistenceError {
            return error
        }
    }

    private func assertContentFree(
        _ error: WorkspaceSettingsPersistenceError,
        secrets: [String]
    ) {
        for secret in secrets {
            XCTAssertFalse(error.description.contains(secret))
        }
    }
}
