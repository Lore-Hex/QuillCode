import XCTest
@testable import QuillCodeCore

final class CoreModelTests: XCTestCase {
    func testTrustedRouterDefaults() {
        XCTAssertEqual(TrustedRouterDefaults.fastModel, "trustedrouter/fast")
        XCTAssertEqual(TrustedRouterDefaults.fusionModel, "tr/fusion")
        XCTAssertEqual(TrustedRouterDefaults.defaultModel, TrustedRouterDefaults.fastModel)
        XCTAssertEqual(TrustedRouterDefaults.recommendedModelIDs, [TrustedRouterDefaults.fastModel, TrustedRouterDefaults.fusionModel])
        XCTAssertEqual(TrustedRouterDefaults.canonicalProvider("tr"), TrustedRouterDefaults.trustedRouterProvider)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("trustedrouter/fusion"), TrustedRouterDefaults.fusionModel)
        XCTAssertEqual(TrustedRouterDefaults.provider(fromModelID: "tr/fusion"), TrustedRouterDefaults.trustedRouterProvider)
        XCTAssertEqual(TrustedRouterDefaults.safetyPrimaryModel, "glm-5.2")
        XCTAssertEqual(TrustedRouterDefaults.safetyFallbackModel, "kimi-k2.6")
        XCTAssertLessThan(
            TrustedRouterDefaults.modelSortKey(id: TrustedRouterDefaults.fastModel, provider: "trustedrouter", displayName: "Fast"),
            TrustedRouterDefaults.modelSortKey(id: TrustedRouterDefaults.fusionModel, provider: "tr", displayName: "Fusion")
        )
        XCTAssertLessThan(
            TrustedRouterDefaults.modelCategoryRank(TrustedRouterDefaults.recommendedCategory),
            TrustedRouterDefaults.modelCategoryRank(TrustedRouterDefaults.safetyCategory)
        )
    }

    func testToolCallRoundTrips() throws {
        let call = ToolCall(name: "host.shell.run", argumentsJSON: #"{"cmd":"whoami"}"#)
        let encoded = try JSONHelpers.encodePretty(call)
        let decoded = try JSONHelpers.decode(ToolCall.self, from: encoded)
        XCTAssertEqual(decoded.name, call.name)
        XCTAssertEqual(decoded.argumentsJSON, call.argumentsJSON)
    }

    func testToolCallRedactsEnvironmentValuesForTranscript() {
        let call = ToolCall(
            id: "tool-redact",
            name: "host.shell.run",
            argumentsJSON: #"{"cmd":"printf ok","environment":{"QUILL_TOKEN":"secret-value","CACHE_DIR":".cache/quill"}}"#
        )

        let redacted = call.redactedForTranscript()

        XCTAssertEqual(redacted.id, call.id)
        XCTAssertEqual(redacted.name, call.name)
        XCTAssertTrue(redacted.argumentsJSON.contains(#""cmd""#))
        XCTAssertTrue(redacted.argumentsJSON.contains("printf ok"))
        XCTAssertTrue(redacted.argumentsJSON.contains("QUILL_TOKEN"))
        XCTAssertTrue(redacted.argumentsJSON.contains("CACHE_DIR"))
        XCTAssertTrue(redacted.argumentsJSON.contains(ToolCall.redactedEnvironmentValue))
        XCTAssertFalse(redacted.argumentsJSON.contains("secret-value"))
        XCTAssertFalse(redacted.argumentsJSON.contains(".cache/quill"))
    }

    func testAgentPlanUpdateRoundTrips() throws {
        let update = AgentPlanUpdate(
            explanation: "Keep the user informed.",
            plan: [
                AgentPlanItem(step: "Inspect state", status: .completed),
                AgentPlanItem(step: "Implement change", status: .inProgress, detail: "Keep the slice reviewable."),
                AgentPlanItem(step: "Validate", status: .pending)
            ]
        )

        let encoded = try JSONHelpers.encodePretty(update)
        let decoded = try JSONHelpers.decode(AgentPlanUpdate.self, from: encoded)

        XCTAssertEqual(decoded, update)
        XCTAssertEqual(ToolDefinition.planUpdate.name, "host.plan.update")
        XCTAssertEqual(AgentPlanItemStatus.inProgress.label, "Running")
        XCTAssertTrue(ToolDefinition.planUpdate.parametersJSON.contains("in_progress"))
        XCTAssertEqual(ToolDefinition.memoryRemember.name, "host.memory.remember")
        XCTAssertEqual(ToolDefinition.memoryRemember.risk, .append)
        XCTAssertTrue(ToolDefinition.memoryRemember.parametersJSON.contains(#""content""#))
    }

    func testToolArgumentsRejectMissingCommand() throws {
        let args = try ToolArguments("{}")
        XCTAssertThrowsError(try args.requiredString("cmd"))
    }

    func testToolArgumentsParseIntegerValues() throws {
        let args = try ToolArguments(#"{"x":42,"y":"84","dx":1,"dy":-2}"#)

        XCTAssertEqual(try args.requiredInt("x"), 42)
        XCTAssertEqual(try args.requiredInt("y"), 84)
        XCTAssertEqual(try args.requiredInt("dx"), 1)
        XCTAssertEqual(try args.requiredInt("dy"), -2)
        XCTAssertThrowsError(try args.requiredInt("z"))
    }

    func testToolArgumentsParseBooleanValues() throws {
        let args = try ToolArguments(#"{"enabled":true,"disabled":false}"#)

        XCTAssertEqual(args.bool("enabled"), true)
        XCTAssertEqual(args.bool("disabled"), false)
        XCTAssertNil(args.bool("missing"))
    }

    func testToolArgumentsParseStringDictionaries() throws {
        let args = try ToolArguments(#"{"environment":{"QUILL_ENV":"dev","CACHE_DIR":".cache/quill"},"ignored":{"count":1}}"#)

        XCTAssertEqual(args.stringDictionary("environment"), [
            "CACHE_DIR": ".cache/quill",
            "QUILL_ENV": "dev"
        ])
        XCTAssertNil(args.stringDictionary("ignored"))
        XCTAssertNil(args.stringDictionary("missing"))
    }

    func testModelCatalogNormalizationDeduplicatesAliasesAndSortsDefaultsFirst() {
        let catalog = TrustedRouterDefaults.normalizedModelCatalog([
            .init(id: "acme/code-pro", provider: "acme", displayName: "Code Pro", category: "Coding"),
            .init(id: "trustedrouter/fusion", provider: "trustedrouter", displayName: "Fusion Alias", category: "Recommended"),
            .init(id: "tr/fast", provider: "tr", displayName: "Fast Alias", category: "Recommended")
        ])

        XCTAssertEqual(catalog.prefix(2).map(\.id), TrustedRouterDefaults.recommendedModelIDs)
        XCTAssertEqual(catalog.filter { $0.id == TrustedRouterDefaults.fastModel }.count, 1)
        XCTAssertEqual(catalog.filter { $0.id == TrustedRouterDefaults.fusionModel }.count, 1)
        XCTAssertTrue(catalog.contains { $0.id == "acme/code-pro" })
    }

    func testProjectConnectionParsesSSHAddresses() throws {
        let scpStyle = try XCTUnwrap(ProjectConnection.parseSSH("quill@feather.local:/srv/quill"))
        XCTAssertEqual(scpStyle, .ssh(path: "/srv/quill", host: "feather.local", user: "quill"))
        XCTAssertEqual(scpStyle.displayLabel, "ssh://quill@feather.local/srv/quill")

        let urlStyle = try XCTUnwrap(ProjectConnection.parseSSH("ssh://root@example.com:2222/opt/app"))
        XCTAssertEqual(urlStyle.path, "/opt/app")
        XCTAssertEqual(urlStyle.host, "example.com")
        XCTAssertEqual(urlStyle.user, "root")
        XCTAssertEqual(urlStyle.port, 2222)
        XCTAssertEqual(urlStyle.displayLabel, "ssh://root@example.com:2222/opt/app")

        XCTAssertNil(ProjectConnection.parseSSH("not a remote"))
        XCTAssertNil(ProjectConnection.parseSSH("host:relative/path"))
    }

    func testBrowserInspectionOutputDecodesOlderPayloadWithoutInspectionDepth() throws {
        let output = try JSONHelpers.decode(BrowserInspectionToolOutput.self, from: """
        {
          "url": "http://localhost:5173",
          "title": "Preview",
          "status": "Preview ready",
          "sourceLabel": "Local web app",
          "summary": "Ready",
          "details": ["Host: localhost"],
          "outline": ["Page: localhost"],
          "comments": []
        }
        """)

        XCTAssertEqual(output.inspectionDepth, .metadataOnly)
        XCTAssertEqual(output.inspectionDepth.label, "Metadata only")
    }

    func testAppConfigDecodesOlderPayloadWithoutFavorites() throws {
        let config = try JSONHelpers.decode(AppConfig.self, from: """
        {
          "defaultModel": "trustedrouter/fusion",
          "mode": "auto",
          "apiBaseURL": "https://api.trustedrouter.com/v1",
          "authMode": "oauth",
          "developerOverrideEnabled": false
        }
        """)

        XCTAssertEqual(config.defaultModel, TrustedRouterDefaults.fusionModel)
        XCTAssertEqual(config.favoriteModels, [])
    }

    func testProjectAndThreadDecodeOlderStateWithoutInstructions() throws {
        let projectID = UUID()
        let date = ISO8601DateFormatter().string(from: Date())
        let project = try JSONHelpers.decode(ProjectRef.self, from: """
        {
          "id": "\(projectID.uuidString)",
          "name": "QuillCode",
          "path": "/tmp/QuillCode",
          "lastOpenedAt": "\(date)"
        }
        """)
        XCTAssertEqual(project.instructions, [])
        XCTAssertEqual(project.localActions, [])
        XCTAssertEqual(project.memories, [])

        let threadID = UUID()
        let thread = try JSONHelpers.decode(ChatThread.self, from: """
        {
          "id": "\(threadID.uuidString)",
          "title": "Old thread",
          "projectID": "\(projectID.uuidString)",
          "mode": "auto",
          "model": "trustedrouter/fusion",
          "messages": [],
          "events": [],
          "isPinned": false,
          "isArchived": false,
          "createdAt": "\(date)",
          "updatedAt": "\(date)"
        }
        """)
        XCTAssertEqual(thread.model, TrustedRouterDefaults.fusionModel)
        XCTAssertEqual(thread.instructions, [])
        XCTAssertEqual(thread.memories, [])
    }
}
