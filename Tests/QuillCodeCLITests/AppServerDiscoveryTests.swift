import Foundation
import QuillCodeAgent
@testable import QuillCodeCLI
import QuillCodeCore
import QuillCodePersistence
import QuillCodeSafety
import XCTest

final class AppServerDiscoveryTests: XCTestCase {
    func testModelListProjectsCatalogAndPaginatesDeterministically() async throws {
        let fixture = try await makeSession()

        try await fixture.request(id: 1, method: "model/list", params: ["limit": 2])
        var records = try await fixture.output.records()
        let first = try XCTUnwrap(result(for: 1, in: records))
        let firstPage = try XCTUnwrap(first["data"]?.arrayValue?.compactMap(\.objectValue))
        let cursor = try XCTUnwrap(first["nextCursor"]?.stringValue)
        XCTAssertEqual(firstPage.count, 2)
        XCTAssertEqual(firstPage.first?["displayName"]?.stringValue, "Nike 1.0")
        assertModelShape(try XCTUnwrap(firstPage.first))

        try await fixture.request(
            id: 2,
            method: "model/list",
            params: ["cursor": cursor, "limit": 2]
        )
        try await fixture.request(id: 3, method: "model/list", params: ["limit": 1_000])
        try await fixture.request(id: 4, method: "model/list", params: ["cursor": "invalid"])
        try await fixture.request(id: 5, method: "model/list", params: ["limit": 0])
        try await fixture.request(id: 6, method: "model/list", params: ["includeHidden": "yes"])

        records = try await fixture.output.records()
        let secondPage = try XCTUnwrap(result(for: 2, in: records)?["data"]?.arrayValue)
        XCTAssertEqual(secondPage.count, 2)
        XCTAssertNotEqual(
            firstPage.last?["id"]?.stringValue,
            secondPage.first?.objectValue?["id"]?.stringValue
        )
        let allModels = try XCTUnwrap(
            result(for: 3, in: records)?["data"]?.arrayValue?.compactMap(\.objectValue)
        )
        XCTAssertEqual(allModels.filter { $0["isDefault"]?.boolValue == true }.count, 1)
        XCTAssertEqual(
            allModels.first { $0["isDefault"]?.boolValue == true }?["id"]?.stringValue,
            TrustedRouterDefaults.defaultModel
        )
        for id in 4...6 {
            XCTAssertEqual(errorCode(for: id, in: records), -32_602)
        }
    }

    func testProviderCapabilitiesMatchImplementedTrustedRouterSurface() async throws {
        let fixture = try await makeSession()
        try await fixture.request(id: 1, method: "modelProvider/capabilities/read")
        try await fixture.request(
            id: 2,
            method: "modelProvider/capabilities/read",
            params: ["provider": "trustedrouter"]
        )

        let records = try await fixture.output.records()
        XCTAssertEqual(result(for: 1, in: records), [
            "namespaceTools": .bool(false),
            "imageGeneration": .bool(false),
            "webSearch": .bool(true)
        ])
        XCTAssertEqual(errorCode(for: 2, in: records), -32_602)
    }

    func testAccountReadReportsCredentialPresenceWithoutExposingSecret() async throws {
        let secret = "test-secret-that-must-not-appear"
        let authenticated = try await makeSession(apiKey: "  \(secret)  ")
        try await authenticated.request(
            id: 1,
            method: "account/read",
            params: ["refreshToken": true]
        )

        let authenticatedRecords = try await authenticated.output.records()
        let account = try XCTUnwrap(result(for: 1, in: authenticatedRecords)?["account"]?.objectValue)
        XCTAssertEqual(account, ["type": .string("apiKey")])
        XCTAssertEqual(
            result(for: 1, in: authenticatedRecords)?["requiresOpenaiAuth"]?.boolValue,
            false
        )
        let encoded = String(decoding: try JSONEncoder().encode(authenticatedRecords), as: UTF8.self)
        XCTAssertFalse(encoded.contains(secret))

        let anonymous = try await makeSession()
        try await anonymous.request(id: 1, method: "account/read")
        let anonymousRecords = try await anonymous.output.records()
        XCTAssertEqual(result(for: 1, in: anonymousRecords)?["account"], .null)
    }

    func testCredentialResolutionUsesExplicitEnvironmentThenStoredPrecedence() throws {
        let directory = try temporaryDirectory(prefix: "app-server-credentials")
        let store = SecretTrustedRouterSessionStore(
            secretStore: FileSecretStore(directory: directory)
        )
        try store.saveAPIKey("stored-key")

        XCTAssertEqual(
            try CLITrustedRouterCredentials.resolve(
                explicit: " explicit-key ",
                environment: ["QUILLCODE_API_KEY": "environment-key"],
                sessionStore: store
            ),
            "explicit-key"
        )
        XCTAssertEqual(
            try CLITrustedRouterCredentials.resolve(
                explicit: nil,
                environment: ["QUILLCODE_API_KEY": " environment-key "],
                sessionStore: store
            ),
            "environment-key"
        )
        XCTAssertEqual(
            try CLITrustedRouterCredentials.resolve(
                explicit: "  ",
                environment: [:],
                sessionStore: store
            ),
            "stored-key"
        )
    }

    func testAccountUsageAggregatesPersistedLocalTokenEventsByUTCDay() async throws {
        let calendar = utcCalendar
        let today = calendar.startOfDay(for: Date())
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        let earlier = try XCTUnwrap(calendar.date(byAdding: .day, value: -3, to: today))
        let thread = ChatThread(events: [
            usageEvent(tokens: 100, createdAt: today.addingTimeInterval(300)),
            usageEvent(tokens: 200, createdAt: yesterday.addingTimeInterval(300)),
            usageEvent(tokens: 50, createdAt: earlier.addingTimeInterval(300))
        ])
        let fixture = try await makeSession(threads: [thread])
        try await fixture.request(id: 1, method: "account/usage/read")

        let records = try await fixture.output.records()
        let response = try XCTUnwrap(result(for: 1, in: records))
        let summary = try XCTUnwrap(response["summary"]?.objectValue)
        XCTAssertEqual(summary["lifetimeTokens"]?.numberValue, 350)
        XCTAssertEqual(summary["peakDailyTokens"]?.numberValue, 200)
        XCTAssertEqual(summary["currentStreakDays"]?.numberValue, 2)
        XCTAssertEqual(summary["longestStreakDays"]?.numberValue, 2)
        XCTAssertEqual(summary["longestRunningTurnSec"], .null)
        let buckets = try XCTUnwrap(response["dailyUsageBuckets"]?.arrayValue?.compactMap(\.objectValue))
        XCTAssertEqual(buckets.count, 3)
        XCTAssertEqual(buckets.map { $0["tokens"]?.numberValue }, [50, 200, 100])
        XCTAssertEqual(buckets.last?["startDate"]?.stringValue, utcDayString(today))
    }

    func testRateLimitsExposeOnlyNamedLocalSpendControls() async throws {
        let config = AppConfig(
            runSpendPeriodLimits: RunSpendPeriodLimits(dailyUSD: 5, weeklyUSD: 20)
        )
        let fixture = try await makeSession(config: config)
        try await fixture.request(id: 1, method: "account/rateLimits/read")

        let records = try await fixture.output.records()
        let response = try XCTUnwrap(result(for: 1, in: records))
        let legacy = try XCTUnwrap(response["rateLimits"]?.objectValue)
        XCTAssertEqual(legacy["limitId"]?.stringValue, "quillcode-local-daily")
        XCTAssertEqual(
            legacy["limitName"]?.stringValue,
            "QuillCode local daily spend control"
        )
        XCTAssertEqual(legacy["primary"]?.objectValue?["usedPercent"]?.numberValue, 0)
        XCTAssertEqual(legacy["individualLimit"]?.objectValue?["limit"]?.stringValue, "5")
        let controls = try XCTUnwrap(response["rateLimitsByLimitId"]?.objectValue)
        XCTAssertEqual(Set(controls.keys), ["quillcode-local-daily", "quillcode-local-weekly"])
        XCTAssertEqual(response["rateLimitResetCredits"], .null)

        let unlimited = try await makeSession()
        try await unlimited.request(id: 1, method: "account/rateLimits/read")
        let unlimitedRecords = try await unlimited.output.records()
        let unlimitedResponse = try XCTUnwrap(result(for: 1, in: unlimitedRecords))
        XCTAssertEqual(unlimitedResponse["rateLimitsByLimitId"], .null)
        XCTAssertEqual(unlimitedResponse["rateLimits"]?.objectValue?["limitId"], .null)
    }

    func testConfigReadProjectsEffectiveConfigAndOptionalUserLayer() async throws {
        let config = AppConfig(
            defaultModel: TrustedRouterDefaults.socratesModel,
            mode: .auto,
            runSpendPeriodLimits: RunSpendPeriodLimits(dailyUSD: 5),
            reviewModel: TrustedRouterDefaults.aristotleModel
        )
        let fixture = try await makeSession(
            apiKey: "must-not-leak",
            model: TrustedRouterDefaults.prometheusModel,
            config: config
        )
        try await fixture.request(
            id: 1,
            method: "config/read",
            params: ["includeLayers": true, "cwd": fixture.workspace.path]
        )
        try await fixture.request(
            id: 2,
            method: "config/read",
            params: ["cwd": fixture.workspace.appendingPathComponent("missing").path]
        )

        let records = try await fixture.output.records()
        let response = try XCTUnwrap(result(for: 1, in: records))
        let effective = try XCTUnwrap(response["config"]?.objectValue)
        XCTAssertEqual(effective["model"]?.stringValue, TrustedRouterDefaults.prometheusModel)
        XCTAssertEqual(effective["review_model"]?.stringValue, TrustedRouterDefaults.aristotleModel)
        XCTAssertEqual(effective["model_provider"]?.stringValue, "trustedrouter")
        XCTAssertEqual(effective["approval_policy"]?.stringValue, "on-request")
        XCTAssertEqual(effective["approvals_reviewer"]?.stringValue, "auto_review")
        XCTAssertEqual(effective["sandbox_mode"]?.stringValue, "workspace-write")
        XCTAssertEqual(effective["web_search"]?.stringValue, "live")
        XCTAssertEqual(response["origins"]?.objectValue, [:])
        let layers = try XCTUnwrap(response["layers"]?.arrayValue?.compactMap(\.objectValue))
        XCTAssertEqual(layers.count, 1)
        XCTAssertEqual(layers[0]["name"]?.objectValue?["type"]?.stringValue, "user")
        XCTAssertEqual(layers[0]["name"]?.objectValue?["file"]?.stringValue, fixture.configFile.path)
        XCTAssertNotNil(layers[0]["version"]?.stringValue)
        XCTAssertEqual(errorCode(for: 2, in: records), -32_602)
        let encoded = String(decoding: try JSONEncoder().encode(records), as: UTF8.self)
        XCTAssertFalse(encoded.contains("must-not-leak"))
    }

    private func assertModelShape(_ model: [String: CLIJSONValue]) {
        let required = Set([
            "id", "model", "upgrade", "upgradeInfo", "availabilityNux", "displayName",
            "description", "hidden", "supportedReasoningEfforts", "defaultReasoningEffort",
            "inputModalities", "supportsPersonality", "additionalSpeedTiers", "serviceTiers",
            "defaultServiceTier", "isDefault"
        ])
        XCTAssertEqual(Set(model.keys), required)
        XCTAssertEqual(model["inputModalities"]?.arrayValue?.first?.stringValue, "text")
    }

    private func makeSession(
        apiKey: String? = nil,
        model: String? = nil,
        config: AppConfig? = nil,
        threads: [ChatThread] = []
    ) async throws -> DiscoveryFixture {
        let home = try temporaryDirectory(prefix: "app-server-discovery-home")
        let workspace = try temporaryDirectory(prefix: "app-server-discovery-workspace")
        let paths = QuillCodePaths(home: home)
        try paths.ensure()
        if let config { try ConfigStore(fileURL: paths.configFile).save(config) }
        let store = JSONThreadStore(directory: paths.threadsDirectory)
        for thread in threads { try store.save(thread) }

        let output = DiscoveryOutputCollector()
        let session = try AppServerSession(
            request: CLIAppServerRequest(
                live: false,
                apiKey: apiKey,
                model: model,
                home: home
            ),
            environment: [:],
            currentDirectory: workspace,
            runnerFactory: { configuration in
                AgentRunner(
                    llm: MockLLMClient(),
                    safety: StaticSafetyReviewer(),
                    maxToolSteps: configuration.appConfig.maxToolSteps
                )
            },
            sink: { line in await output.append(line) }
        )
        let fixture = DiscoveryFixture(
            session: session,
            output: output,
            home: home,
            workspace: workspace,
            configFile: paths.configFile
        )
        try await fixture.request(
            id: 100,
            method: "initialize",
            params: ["clientInfo": ["name": "DiscoveryTests", "version": "1"]]
        )
        try await fixture.notify(method: "initialized")
        return fixture
    }

    private func usageEvent(tokens: Int, createdAt: Date) -> ThreadEvent {
        var event = ModelTokenUsageEvent.event(usage: ModelTokenUsage(totalTokens: tokens))
        event.createdAt = createdAt
        return event
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func utcDayString(_ date: Date) -> String {
        let components = utcCalendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private func result(
        for id: Int,
        in records: [[String: CLIJSONValue]]
    ) -> [String: CLIJSONValue]? {
        records.first { $0["id"]?.numberValue == Double(id) }?["result"]?.objectValue
    }

    private func errorCode(for id: Int, in records: [[String: CLIJSONValue]]) -> Double? {
        records.first { $0["id"]?.numberValue == Double(id) }?["error"]?.objectValue?["code"]?.numberValue
    }

    private func temporaryDirectory(prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}

private struct DiscoveryFixture {
    let session: AppServerSession
    let output: DiscoveryOutputCollector
    let home: URL
    let workspace: URL
    let configFile: URL

    func request(
        id: Int,
        method: String,
        params: [String: Any] = [:]
    ) async throws {
        try await send(["id": id, "method": method, "params": params])
    }

    func notify(method: String, params: [String: Any] = [:]) async throws {
        try await send(["method": method, "params": params])
    }

    private func send(_ value: [String: Any]) async throws {
        await session.receive(try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]))
    }
}

private actor DiscoveryOutputCollector {
    private var lines: [String] = []

    func append(_ line: String) {
        lines.append(line)
    }

    func records() throws -> [[String: CLIJSONValue]] {
        try lines.map { line in
            guard let object = try CLIJSONCodec.decode(line).objectValue else {
                throw DiscoveryTestError.invalidRecord
            }
            return object
        }
    }
}

private enum DiscoveryTestError: Error {
    case invalidRecord
}
