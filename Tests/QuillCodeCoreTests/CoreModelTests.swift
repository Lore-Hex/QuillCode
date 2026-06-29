import XCTest
@testable import QuillCodeCore

final class CoreModelTests: XCTestCase {
    func testTrustedRouterDefaults() {
        XCTAssertEqual(TrustedRouterDefaults.fastModel, "trustedrouter/fast")
        XCTAssertEqual(TrustedRouterDefaults.synthModel, "tr/synth")
        XCTAssertEqual(TrustedRouterDefaults.synthCodeModel, "tr/synth-code")
        XCTAssertEqual(TrustedRouterDefaults.synthSlashAlias, "/synth")
        XCTAssertEqual(TrustedRouterDefaults.synthCodeSlashAlias, "/synth-code")
        XCTAssertEqual(TrustedRouterDefaults.displayName(fromModelID: TrustedRouterDefaults.fastModel), "Nike 1.0")
        XCTAssertEqual(TrustedRouterDefaults.displayName(fromModelID: TrustedRouterDefaults.synthModel), "Synth")
        XCTAssertEqual(TrustedRouterDefaults.displayName(fromModelID: TrustedRouterDefaults.synthCodeModel), "Synth Code")
        XCTAssertEqual(TrustedRouterDefaults.preferredDisplayModelID(TrustedRouterDefaults.synthModel), "/synth")
        XCTAssertEqual(TrustedRouterDefaults.preferredDisplayModelID(TrustedRouterDefaults.synthCodeModel), "/synth-code")
        XCTAssertEqual(TrustedRouterDefaults.preferredDisplayModelID("trustedrouter/fusion"), "/synth")
        XCTAssertEqual(TrustedRouterDefaults.preferredDisplayModelID("trustedrouter/fusion-code"), "/synth-code")
        XCTAssertEqual(TrustedRouterDefaults.preferredDisplayModelID(TrustedRouterDefaults.fastModel), "trustedrouter/fast")
        XCTAssertEqual(TrustedRouterDefaults.defaultModel, TrustedRouterDefaults.fastModel)
        XCTAssertEqual(
            TrustedRouterDefaults.recommendedModelIDs,
            [
                TrustedRouterDefaults.socratesModel,
                TrustedRouterDefaults.fastModel,
                TrustedRouterDefaults.synthModel,
                TrustedRouterDefaults.synthCodeModel
            ]
        )
        XCTAssertEqual(TrustedRouterDefaults.displayName(fromModelID: TrustedRouterDefaults.socratesModel), "Socrates 1.1")
        XCTAssertEqual(TrustedRouterDefaults.preferredDisplayModelID(TrustedRouterDefaults.socratesModel), "/socrates")
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("socrates-1.1"), TrustedRouterDefaults.socratesModel)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("/socrates"), TrustedRouterDefaults.socratesModel)
        XCTAssertEqual(TrustedRouterDefaults.canonicalProvider("tr"), TrustedRouterDefaults.trustedRouterProvider)
        XCTAssertEqual(TrustedRouterDefaults.canonicalProvider(" TR "), TrustedRouterDefaults.trustedRouterProvider)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("Nike 1.0"), TrustedRouterDefaults.fastModel)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("/fast"), TrustedRouterDefaults.fastModel)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("tr/synth"), TrustedRouterDefaults.synthModel)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("Synth"), TrustedRouterDefaults.synthModel)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("trustedrouter/synth"), TrustedRouterDefaults.synthModel)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID(TrustedRouterDefaults.synthSlashAlias), TrustedRouterDefaults.synthModel)
        XCTAssertEqual(TrustedRouterDefaults.provider(fromModelID: TrustedRouterDefaults.synthSlashAlias), TrustedRouterDefaults.trustedRouterProvider)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("tr/fusion"), TrustedRouterDefaults.synthModel)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("FUSION"), TrustedRouterDefaults.synthModel)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("trustedrouter/fusion"), TrustedRouterDefaults.synthModel)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("/fusion"), TrustedRouterDefaults.synthModel)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("tr/synth-code"), TrustedRouterDefaults.synthCodeModel)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("Synth Code"), TrustedRouterDefaults.synthCodeModel)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("trustedrouter/synth-code"), TrustedRouterDefaults.synthCodeModel)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID(TrustedRouterDefaults.synthCodeSlashAlias), TrustedRouterDefaults.synthCodeModel)
        XCTAssertEqual(TrustedRouterDefaults.provider(fromModelID: TrustedRouterDefaults.synthCodeSlashAlias), TrustedRouterDefaults.trustedRouterProvider)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("tr/fusion-code"), TrustedRouterDefaults.synthCodeModel)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("trustedrouter/fusion-code"), TrustedRouterDefaults.synthCodeModel)
        XCTAssertEqual(TrustedRouterDefaults.canonicalModelID("/fusion-code"), TrustedRouterDefaults.synthCodeModel)
        XCTAssertEqual(TrustedRouterDefaults.safetyPrimaryModel, "glm-5.2")
        XCTAssertEqual(TrustedRouterDefaults.safetyFallbackModel, "kimi-k2.6")
        XCTAssertLessThan(
            TrustedRouterDefaults.modelSortKey(id: TrustedRouterDefaults.fastModel, provider: "trustedrouter", displayName: "Nike 1.0"),
            TrustedRouterDefaults.modelSortKey(id: TrustedRouterDefaults.synthModel, provider: "tr", displayName: "Synth")
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
        XCTAssertEqual(ToolDefinition.browserOpen.name, "host.browser.open")
        XCTAssertEqual(ToolDefinition.browserOpen.host, .browser)
        XCTAssertEqual(ToolDefinition.browserOpen.risk, .read)
        XCTAssertTrue(ToolDefinition.browserOpen.parametersJSON.contains(#""url""#))
        XCTAssertEqual(ToolDefinition.memoryRemember.name, "host.memory.remember")
        XCTAssertEqual(ToolDefinition.memoryRemember.risk, .append)
        XCTAssertTrue(ToolDefinition.memoryRemember.parametersJSON.contains(#""content""#))
    }

    func testAgentHandoffUpdateRoundTrips() throws {
        let update = AgentHandoffUpdate(
            summary: "Implemented the focused slice and ran validation.",
            nextSteps: ["Review the PR", "Merge once CI is green"]
        )

        let encoded = try JSONHelpers.encodePretty(update)
        let decoded = try JSONHelpers.decode(AgentHandoffUpdate.self, from: encoded)

        XCTAssertEqual(decoded, update)
        XCTAssertEqual(ToolDefinition.handoffUpdate.name, "host.handoff.update")
        XCTAssertEqual(ToolDefinition.handoffUpdate.host, .local)
        XCTAssertEqual(ToolDefinition.handoffUpdate.risk, .read)
        XCTAssertTrue(ToolDefinition.handoffUpdate.parametersJSON.contains(#""summary""#))
        XCTAssertTrue(ToolDefinition.handoffUpdate.parametersJSON.contains(#""nextSteps""#))
    }

    func testSubagentProgressUpdateRoundTrips() throws {
        let update = SubagentProgressUpdate(
            objective: "Review the current task in parallel.",
            subagents: [
                SubagentProgressItem(
                    name: "Explorer",
                    role: "Find relevant files.",
                    status: .completed,
                    summary: "Mapped the Activity pane."
                ),
                SubagentProgressItem(
                    name: "Verifier",
                    role: "Run focused checks.",
                    status: .running
                ),
                SubagentProgressItem(
                    name: "Frontend/UX",
                    role: "Inspect the interaction flow.",
                    status: .blocked,
                    summary: "Waiting on design notes.",
                    groupPath: ["Frontend"]
                )
            ]
        )

        let encoded = try JSONHelpers.encodePretty(update)
        let decoded = try JSONHelpers.decode(SubagentProgressUpdate.self, from: encoded)

        XCTAssertEqual(decoded, update)
        XCTAssertEqual(decoded.subagents[2].groupPath, ["Frontend"])
        XCTAssertEqual(ToolDefinition.subagentsUpdate.name, "host.subagents.update")
        XCTAssertEqual(ToolDefinition.subagentsUpdate.host, .local)
        XCTAssertEqual(ToolDefinition.subagentsUpdate.risk, .read)
        XCTAssertEqual(SubagentStatus.completed.label, "Done")
        XCTAssertEqual(SubagentStatus.cancelled.label, "Cancelled")
        XCTAssertTrue(ToolDefinition.subagentsUpdate.parametersJSON.contains(#""subagents""#))
        XCTAssertTrue(ToolDefinition.subagentsUpdate.parametersJSON.contains(#""groupPath""#))
        XCTAssertTrue(ToolDefinition.subagentsUpdate.parametersJSON.contains("blocked"))
        XCTAssertTrue(ToolDefinition.subagentsUpdate.parametersJSON.contains("cancelled"))
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
        let args = try ToolArguments(#"{"enabled":true,"disabled":false,"stringEnabled":"yes","stringDisabled":"0"}"#)

        XCTAssertEqual(args.bool("enabled"), true)
        XCTAssertEqual(args.bool("disabled"), false)
        XCTAssertEqual(args.bool("stringEnabled"), true)
        XCTAssertEqual(args.bool("stringDisabled"), false)
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

    func testToolArgumentsJSONSerializesMixedValuesInStableOrder() {
        let json = ToolArguments.json([
            "cmd": "build",
            "force": true,
            "timeoutSeconds": 30,
            "environment": ["QUILL_ENV": "test"]
        ])

        XCTAssertEqual(
            json,
            #"{"cmd":"build","environment":{"QUILL_ENV":"test"},"force":true,"timeoutSeconds":30}"#
        )
    }

    func testModelCatalogNormalizationDeduplicatesAliasesAndSortsDefaultsFirst() {
        let catalog = TrustedRouterDefaults.normalizedModelCatalog([
            .init(id: "acme/code-pro", provider: "acme", displayName: "Code Pro", category: "Coding"),
            .init(id: "/synth", provider: "trustedrouter", displayName: "Synth Alias", category: "Recommended"),
            .init(id: "trustedrouter/fusion", provider: "trustedrouter", displayName: "Legacy Fusion", category: "Recommended"),
            .init(id: "/synth-code", provider: "trustedrouter", displayName: "Synth Code Alias", category: "Recommended"),
            .init(id: "/fusion-code", provider: "trustedrouter", displayName: "Legacy Fusion Code", category: "Recommended"),
            .init(id: "tr/fast", provider: "tr", displayName: "Fast Alias", category: "Recommended")
        ])

        XCTAssertEqual(catalog.prefix(TrustedRouterDefaults.recommendedModelIDs.count).map(\.id), TrustedRouterDefaults.recommendedModelIDs)
        XCTAssertEqual(catalog.filter { $0.id == TrustedRouterDefaults.socratesModel }.count, 1)
        XCTAssertEqual(catalog.filter { $0.id == TrustedRouterDefaults.fastModel }.count, 1)
        XCTAssertEqual(catalog.filter { $0.id == TrustedRouterDefaults.synthModel }.count, 1)
        XCTAssertEqual(catalog.filter { $0.id == TrustedRouterDefaults.synthCodeModel }.count, 1)
        XCTAssertFalse(catalog.contains { $0.id.contains("fusion") })
        XCTAssertFalse(catalog.contains { $0.displayName.contains("Fusion") })
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

    func testBrowserInspectionDepthLabelsAreStable() {
        XCTAssertEqual(BrowserInspectionDepth.metadataOnly.rawValue, "metadata_only")
        XCTAssertEqual(BrowserInspectionDepth.metadataOnly.label, "Metadata only")
        XCTAssertEqual(BrowserInspectionDepth.fileMetadata.rawValue, "file_metadata")
        XCTAssertEqual(BrowserInspectionDepth.fileMetadata.label, "File metadata")
        XCTAssertEqual(BrowserInspectionDepth.staticHTMLSnapshot.rawValue, "static_html_snapshot")
        XCTAssertEqual(BrowserInspectionDepth.staticHTMLSnapshot.label, "Static HTML snapshot")
        XCTAssertEqual(BrowserInspectionDepth.networkHTMLSnapshot.rawValue, "network_html_snapshot")
        XCTAssertEqual(BrowserInspectionDepth.networkHTMLSnapshot.label, "Network HTML snapshot")
        XCTAssertEqual(BrowserInspectionDepth.liveDOMSnapshot.rawValue, "live_dom_snapshot")
        XCTAssertEqual(BrowserInspectionDepth.liveDOMSnapshot.label, "Live DOM snapshot")
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

        XCTAssertEqual(config.defaultModel, TrustedRouterDefaults.synthModel)
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
        XCTAssertEqual(thread.model, TrustedRouterDefaults.synthModel)
        XCTAssertEqual(thread.instructions, [])
        XCTAssertEqual(thread.memories, [])
    }

    func testProjectInstructionDerivesScopedApplicabilityFromPath() throws {
        XCTAssertEqual(ProjectInstruction.scopePath(for: "AGENTS.md"), ".")
        XCTAssertEqual(ProjectInstruction.scopePath(for: ".quillcode/rules.md"), ".")
        XCTAssertEqual(ProjectInstruction.scopePath(for: "Sources/Feature/AGENTS.md"), "Sources/Feature")
        XCTAssertEqual(ProjectInstruction.scopePath(for: "Sources/Feature/.quillcode/rules.md"), "Sources/Feature")
        XCTAssertEqual(ProjectInstruction.scopePath(for: "Sources/Feature/.quillcode/instructions.md"), "Sources/Feature")

        let instruction = ProjectInstruction(
            path: "Sources/Feature/AGENTS.md",
            title: "Feature rules",
            content: "Prefer feature tests.",
            byteCount: 21
        )

        XCTAssertEqual(instruction.scopePath, "Sources/Feature")
        XCTAssertEqual(instruction.scopeLabel, "Sources/Feature/**")
        XCTAssertEqual(ProjectInstruction.scopeLabel(for: "."), "whole project")
        XCTAssertEqual(ProjectInstruction.scopeLabel(for: "Sources"), "Sources/**")
    }

    func testProjectInstructionDecodesOlderPayloadWithoutScopePath() throws {
        let instruction = try JSONHelpers.decode(ProjectInstruction.self, from: """
        {
          "path": "Sources/Feature/.quillcode/rules.md",
          "title": "Feature rules",
          "content": "Prefer feature tests.",
          "byteCount": 21,
          "wasTruncated": false
        }
        """)

        XCTAssertEqual(instruction.scopePath, "Sources/Feature")
        XCTAssertEqual(instruction.scopeLabel, "Sources/Feature/**")
    }
}
