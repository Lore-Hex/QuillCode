import Foundation
import QuillCodeAgent
@testable import QuillCodeCLI
import QuillCodeCore
import QuillCodePersistence
import QuillCodeSafety
import XCTest

final class AppServerAccountAuthenticationTests: XCTestCase {
    func testDefaultBrowserLoginUsesTrustedRouterAllowlistedCallbackURL() throws {
        XCTAssertEqual(
            try DefaultAppServerAccountLoginStarter.trustedRouterCallbackURL.absoluteString,
            TrustedRouterDefaults.loopbackCallbackURL
        )
    }

    func testAPIKeyLoginPersistsSecretAndEmitsOrderedNonSecretNotifications() async throws {
        let fixture = try await makeSession()
        let secret = "sk-tr-v1-account-test"

        try await fixture.request(
            id: 1,
            method: "account/login/start",
            params: ["type": "apiKey", "apiKey": "  \(secret)  "]
        )

        let records = try await fixture.output.records()
        XCTAssertEqual(records.count, 3)
        XCTAssertEqual(records[0]["id"]?.numberValue, 1)
        XCTAssertEqual(records[0]["result"]?.objectValue?["type"]?.stringValue, "apiKey")
        assertLoginCompleted(records[1], loginID: nil, success: true, error: nil)
        assertAccountUpdated(records[2], authMode: "apikey")
        XCTAssertEqual(try fixture.storedAPIKey(), secret)

        let config = try ConfigStore(fileURL: fixture.paths.configFile).load()
        XCTAssertEqual(config.authMode, .developerOverride)
        XCTAssertTrue(config.developerOverrideEnabled)
        XCTAssertNil(config.trustedRouterAccount)
        let encodedRecords = try await fixture.output.encodedRecords()
        XCTAssertFalse(encodedRecords.contains(secret))
    }

    func testBrowserLoginCompletesAsynchronouslyAndPersistsProfile() async throws {
        let loginDriver = AccountLoginTestDriver()
        let fixture = try await makeSession(accountLoginStarter: loginDriver)

        try await fixture.request(
            id: 1,
            method: "account/login/start",
            params: ["type": "chatgpt", "codexStreamlinedLogin": false]
        )
        var records = try await fixture.output.records()
        XCTAssertEqual(records.count, 1, "OAuth completion must not race ahead of the start response")
        let response = try XCTUnwrap(records[0]["result"]?.objectValue)
        let loginID = try XCTUnwrap(response["loginId"]?.stringValue)
        XCTAssertEqual(response["type"]?.stringValue, "chatgpt")
        XCTAssertEqual(response["authUrl"]?.stringValue, AccountLoginTestDriver.authURL.absoluteString)

        await loginDriver.succeed(
            AppServerAccountCredential(
                apiKey: "oauth-secret",
                profile: TrustedRouterAccountProfile(
                    userID: "user-1",
                    email: "quill@example.com",
                    walletAddress: "0xabc"
                )
            )
        )
        _ = try await fixture.output.waitForNotification(method: "account/updated")

        records = try await fixture.output.records()
        XCTAssertEqual(records.count, 3)
        assertLoginCompleted(records[1], loginID: loginID, success: true, error: nil)
        assertAccountUpdated(records[2], authMode: "apikey")
        XCTAssertEqual(try fixture.storedAPIKey(), "oauth-secret")
        let config = try ConfigStore(fileURL: fixture.paths.configFile).load()
        XCTAssertEqual(config.authMode, .oauth)
        XCTAssertFalse(config.developerOverrideEnabled)
        XCTAssertEqual(config.trustedRouterAccount?.email, "quill@example.com")
        let encodedRecords = try await fixture.output.encodedRecords()
        XCTAssertFalse(encodedRecords.contains("oauth-secret"))
    }

    func testBrowserLoginFailureDoesNotMutateAccount() async throws {
        let loginDriver = AccountLoginTestDriver()
        let fixture = try await makeSession(accountLoginStarter: loginDriver)
        try await fixture.request(id: 1, method: "account/login/start", params: ["type": "chatgpt"])
        let result = try await fixture.output.result(id: 1)
        let loginID = try XCTUnwrap(result?["loginId"]?.stringValue)

        await loginDriver.fail(AccountLoginTestError.exchangeFailed)
        let completed = try await fixture.output.waitForNotification(method: "account/login/completed")

        XCTAssertEqual(completed["loginId"]?.stringValue, loginID)
        XCTAssertEqual(completed["success"]?.boolValue, false)
        XCTAssertTrue(completed["error"]?.stringValue?.contains("exchange failed") == true)
        XCTAssertNil(try fixture.storedAPIKey())
        let updatedCount = try await fixture.output.notificationCount(method: "account/updated")
        XCTAssertEqual(updatedCount, 0)
    }

    func testCancelReturnsCodexStatusAndEmitsExactlyOneCompletion() async throws {
        let loginDriver = AccountLoginTestDriver()
        let fixture = try await makeSession(accountLoginStarter: loginDriver)
        try await fixture.request(id: 1, method: "account/login/start", params: ["type": "chatgpt"])
        let startResult = try await fixture.output.result(id: 1)
        let loginID = try XCTUnwrap(startResult?["loginId"]?.stringValue)

        try await fixture.request(
            id: 2,
            method: "account/login/cancel",
            params: ["loginId": loginID]
        )
        _ = try await fixture.output.waitForNotification(method: "account/login/completed")
        try await fixture.request(
            id: 3,
            method: "account/login/cancel",
            params: ["loginId": loginID]
        )

        let records = try await fixture.output.records()
        let cancelIndex = try XCTUnwrap(records.firstIndex { $0["id"]?.numberValue == 2 })
        let completedIndex = try XCTUnwrap(records.firstIndex {
            $0["method"]?.stringValue == "account/login/completed"
        })
        XCTAssertLessThan(cancelIndex, completedIndex)
        XCTAssertEqual(records[cancelIndex]["result"]?.objectValue?["status"]?.stringValue, "canceled")
        assertLoginCompleted(
            records[completedIndex],
            loginID: loginID,
            success: false,
            error: "cancelled"
        )
        let secondCancelResult = try await fixture.output.result(id: 3)
        let completionCount = try await fixture.output.notificationCount(method: "account/login/completed")
        XCTAssertEqual(secondCancelResult?["status"]?.stringValue, "notFound")
        XCTAssertEqual(completionCount, 1)
        let cancellationCount = try await loginDriver.waitForCancellationCount(1)
        XCTAssertEqual(cancellationCount, 1)
    }

    func testLogoutClearsManagedCredentialAndReportsRemainingExternalCredentialTruthfully() async throws {
        let managed = try await makeSession()
        try await managed.request(
            id: 1,
            method: "account/login/start",
            params: ["type": "apiKey", "apiKey": "stored-key"]
        )
        try await managed.request(id: 2, method: "account/logout")
        try await managed.request(id: 3, method: "account/read")
        XCTAssertNil(try managed.storedAPIKey())
        let managedReadResult = try await managed.output.result(id: 3)
        XCTAssertEqual(managedReadResult?["account"], .null)
        let managedUpdates = try await managed.output.notificationParams(method: "account/updated")
        XCTAssertEqual(managedUpdates.last?["authMode"], .null)

        let external = try await makeSession(explicitAPIKey: "external-key")
        try await external.request(id: 1, method: "account/logout")
        try await external.request(id: 2, method: "account/read")
        let externalReadResult = try await external.output.result(id: 2)
        let externalUpdates = try await external.output.notificationParams(method: "account/updated")
        XCTAssertEqual(externalReadResult?["account"]?.objectValue?["type"]?.stringValue, "apiKey")
        XCTAssertEqual(externalUpdates.last?["authMode"]?.stringValue, "apikey")
    }

    func testNotificationOptOutAndDisconnectCleanupAreHonored() async throws {
        let loginDriver = AccountLoginTestDriver()
        let fixture = try await makeSession(
            accountLoginStarter: loginDriver,
            notificationOptOuts: ["account/login/completed", "account/updated"]
        )
        try await fixture.request(id: 1, method: "account/login/start", params: ["type": "chatgpt"])
        await fixture.session.finishInput()
        await loginDriver.succeed(AppServerAccountCredential(apiKey: "late-key", profile: nil))
        try await Task.sleep(for: .milliseconds(30))

        let cancellationCount = await loginDriver.cancellationCount
        let completionCount = try await fixture.output.notificationCount(method: "account/login/completed")
        let updatedCount = try await fixture.output.notificationCount(method: "account/updated")
        XCTAssertEqual(cancellationCount, 1)
        XCTAssertNil(try fixture.storedAPIKey())
        XCTAssertEqual(completionCount, 0)
        XCTAssertEqual(updatedCount, 0)
    }

    func testRejectsUnsupportedAndMalformedLoginRequests() async throws {
        let fixture = try await makeSession()
        try await fixture.request(id: 1, method: "account/login/start", params: ["type": "apiKey"])
        try await fixture.request(
            id: 2,
            method: "account/login/start",
            params: ["type": "chatgptDeviceCode"]
        )
        try await fixture.request(id: 3, method: "account/login/start", params: ["type": "unknown"])

        let missingKeyError = try await fixture.output.errorCode(id: 1)
        let deviceCodeError = try await fixture.output.errorCode(id: 2)
        let unknownTypeError = try await fixture.output.errorCode(id: 3)
        XCTAssertEqual(missingKeyError, -32602)
        XCTAssertEqual(deviceCodeError, -32602)
        XCTAssertEqual(unknownTypeError, -32602)
    }

    private func makeSession(
        explicitAPIKey: String? = nil,
        accountLoginStarter: any AppServerAccountLoginStarting = AccountLoginTestDriver(),
        notificationOptOuts: [String] = []
    ) async throws -> AccountFixture {
        let home = try temporaryDirectory(prefix: "app-server-account-home")
        let workspace = try temporaryDirectory(prefix: "app-server-account-workspace")
        let paths = QuillCodePaths(home: home)
        try paths.ensure()
        let output = AccountOutputCollector()
        let session = try AppServerSession(
            request: CLIAppServerRequest(live: false, apiKey: explicitAPIKey, home: home),
            environment: [:],
            currentDirectory: workspace,
            runnerFactory: { configuration in
                AgentRunner(
                    llm: MockLLMClient(),
                    safety: StaticSafetyReviewer(),
                    maxToolSteps: configuration.appConfig.maxToolSteps
                )
            },
            accountLoginStarter: accountLoginStarter,
            sink: { line in await output.append(line) }
        )
        let fixture = AccountFixture(session: session, output: output, paths: paths)
        var capabilities: [String: Any] = [:]
        if !notificationOptOuts.isEmpty {
            capabilities["optOutNotificationMethods"] = notificationOptOuts
        }
        try await fixture.request(
            id: 100,
            method: "initialize",
            params: [
                "clientInfo": ["name": "AccountTests", "version": "1"],
                "capabilities": capabilities
            ]
        )
        try await fixture.notify(method: "initialized")
        await output.removeAll()
        return fixture
    }

    private func assertLoginCompleted(
        _ record: [String: CLIJSONValue],
        loginID: String?,
        success: Bool,
        error: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(record["method"]?.stringValue, "account/login/completed", file: file, line: line)
        let params = record["params"]?.objectValue
        XCTAssertEqual(params?["loginId"], loginID.map(CLIJSONValue.string) ?? .null, file: file, line: line)
        XCTAssertEqual(params?["success"]?.boolValue, success, file: file, line: line)
        if let error {
            XCTAssertTrue(params?["error"]?.stringValue?.contains(error) == true, file: file, line: line)
        } else {
            XCTAssertEqual(params?["error"], .null, file: file, line: line)
        }
    }

    private func assertAccountUpdated(
        _ record: [String: CLIJSONValue],
        authMode: String?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(record["method"]?.stringValue, "account/updated", file: file, line: line)
        let params = record["params"]?.objectValue
        XCTAssertEqual(params?["authMode"], authMode.map(CLIJSONValue.string) ?? .null, file: file, line: line)
        XCTAssertEqual(params?["planType"], .null, file: file, line: line)
    }

    private func temporaryDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}

private struct AccountFixture {
    let session: AppServerSession
    let output: AccountOutputCollector
    let paths: QuillCodePaths

    func request(id: Int, method: String, params: [String: Any] = [:]) async throws {
        try await send(["id": id, "method": method, "params": params])
    }

    func notify(method: String, params: [String: Any] = [:]) async throws {
        try await send(["method": method, "params": params])
    }

    func storedAPIKey() throws -> String? {
        try FileSecretStore(directory: paths.secretsDirectory)
            .read(QuillSecretKeys.trustedRouterAPIKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func send(_ value: [String: Any]) async throws {
        await session.receive(try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]))
    }
}

private actor AccountOutputCollector {
    private var lines: [String] = []

    func append(_ line: String) {
        lines.append(line)
    }

    func removeAll() {
        lines.removeAll(keepingCapacity: true)
    }

    func records() throws -> [[String: CLIJSONValue]] {
        try lines.map { line in
            guard let object = try CLIJSONCodec.decode(line).objectValue else {
                throw AccountLoginTestError.invalidRecord
            }
            return object
        }
    }

    func encodedRecords() throws -> String {
        String(decoding: try JSONEncoder().encode(records()), as: UTF8.self)
    }

    func result(id: Int) throws -> [String: CLIJSONValue]? {
        try records().first { $0["id"]?.numberValue == Double(id) }?["result"]?.objectValue
    }

    func errorCode(id: Int) throws -> Double? {
        let record = try records().first { $0["id"]?.numberValue == Double(id) }
        return record?["error"]?.objectValue?["code"]?.numberValue
    }

    func notificationCount(method: String) throws -> Int {
        try records().count { $0["method"]?.stringValue == method }
    }

    func notificationParams(method: String) throws -> [[String: CLIJSONValue]] {
        try records().compactMap { record in
            guard record["method"]?.stringValue == method else { return nil }
            return record["params"]?.objectValue
        }
    }

    func waitForNotification(
        method: String,
        timeout: Duration = .seconds(3)
    ) async throws -> [String: CLIJSONValue] {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let match = try records().first(where: { $0["method"]?.stringValue == method }) {
                return match["params"]?.objectValue ?? [:]
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw AccountLoginTestError.timedOut(method)
    }
}

private actor AccountLoginTestDriver: AppServerAccountLoginStarting {
    nonisolated static let authURL = URL(string: "https://trustedrouter.example/auth")!

    private var result: Result<AppServerAccountCredential, Error>?
    private var continuation: CheckedContinuation<AppServerAccountCredential, Error>?
    private(set) var cancellationCount = 0

    nonisolated func start(baseURL: String) throws -> AppServerAccountBrowserLogin {
        AppServerAccountBrowserLogin(
            authURL: Self.authURL,
            waitForCredential: { try await self.wait() },
            cancel: { Task { await self.cancel() } }
        )
    }

    func succeed(_ credential: AppServerAccountCredential) {
        complete(.success(credential))
    }

    func fail(_ error: Error) {
        complete(.failure(error))
    }

    func waitForCancellationCount(
        _ expected: Int,
        timeout: Duration = .seconds(3)
    ) async throws -> Int {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if cancellationCount >= expected { return cancellationCount }
            try await Task.sleep(for: .milliseconds(10))
        }
        return cancellationCount
    }

    private func wait() async throws -> AppServerAccountCredential {
        if let result {
            self.result = nil
            return try result.get()
        }
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    private func cancel() {
        cancellationCount += 1
        complete(.failure(CancellationError()))
    }

    private func complete(_ result: Result<AppServerAccountCredential, Error>) {
        if let continuation {
            self.continuation = nil
            continuation.resume(with: result)
        } else {
            self.result = result
        }
    }
}

private enum AccountLoginTestError: Error, LocalizedError {
    case exchangeFailed
    case invalidRecord
    case timedOut(String)

    var errorDescription: String? {
        switch self {
        case .exchangeFailed: return "exchange failed"
        case .invalidRecord: return "invalid record"
        case .timedOut(let method): return "timed out waiting for \(method)"
        }
    }
}
