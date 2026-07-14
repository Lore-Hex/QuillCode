import Foundation
import XCTest
@testable import QuillCodeCore

final class ToolSchemaCoreTests: XCTestCase {
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

    func testToolCallRedactsStandardInputForTranscript() {
        let call = ToolCall(
            id: "tool-stdin-redact",
            name: "host.shell.run",
            argumentsJSON: #"{"cmd":"cat","stdin":"private hook payload"}"#
        )

        let redacted = call.redactedForTranscript()

        XCTAssertTrue(redacted.argumentsJSON.contains(ToolCall.redactedStandardInputValue))
        XCTAssertFalse(redacted.argumentsJSON.contains("private hook payload"))
        XCTAssertTrue(redacted.argumentsJSON.contains("cat"))
    }

    func testToolCallRedactsMemoryRememberContentForTranscript() {
        let call = ToolCall(
            id: "tool-memory-redact",
            name: ToolDefinition.memoryRemember.name,
            argumentsJSON: #"{"content":"api_key=SYNTHETIC_TEST_SECRET_DO_NOT_USE","reason":"user gave token"}"#
        )

        let redacted = call.redactedForTranscript()

        XCTAssertEqual(redacted.id, call.id)
        XCTAssertEqual(redacted.name, call.name)
        XCTAssertTrue(redacted.argumentsJSON.contains(ToolCall.redactedMemoryContentValue))
        XCTAssertFalse(redacted.argumentsJSON.contains("SYNTHETIC_TEST_SECRET_DO_NOT_USE"))
        XCTAssertFalse(redacted.argumentsJSON.contains("user gave token"))
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
        XCTAssertEqual(ToolDefinition.browserClick.name, "host.browser.click")
        XCTAssertEqual(ToolDefinition.browserClick.host, .browser)
        XCTAssertEqual(ToolDefinition.browserClick.risk, .append)
        XCTAssertTrue(ToolDefinition.browserClick.parametersJSON.contains(#""selector""#))
        XCTAssertEqual(ToolDefinition.browserType.name, "host.browser.type")
        XCTAssertEqual(ToolDefinition.browserType.host, .browser)
        XCTAssertEqual(ToolDefinition.browserType.risk, .append)
        XCTAssertTrue(ToolDefinition.browserType.parametersJSON.contains(#""text""#))
        XCTAssertEqual(ToolDefinition.browserScript.name, "host.browser.script")
        XCTAssertEqual(ToolDefinition.browserScript.host, .browser)
        XCTAssertEqual(ToolDefinition.browserScript.risk, .append)
        XCTAssertTrue(ToolDefinition.browserScript.parametersJSON.contains(#""source""#))
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
                    summary: "Mapped the Activity pane.",
                    transcript: [
                        SubagentTranscriptEntry(
                            id: "tool-search",
                            kind: .tool,
                            title: "Search files",
                            detail: "Completed - Activity pane",
                            statusLabel: "Done"
                        ),
                        SubagentTranscriptEntry(
                            id: "response",
                            kind: .assistant,
                            title: "Response",
                            detail: "Mapped the Activity pane.",
                            statusLabel: "Answered"
                        )
                    ]
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
        XCTAssertEqual(decoded.subagents[0].transcript.count, 2)
        XCTAssertEqual(decoded.subagents[0].transcript[0].kind, .tool)
        XCTAssertEqual(decoded.subagents[2].groupPath, ["Frontend"])
        XCTAssertEqual(ToolDefinition.subagentsUpdate.name, "host.subagents.update")
        XCTAssertEqual(ToolDefinition.subagentsUpdate.host, .local)
        XCTAssertEqual(ToolDefinition.subagentsUpdate.risk, .read)
        XCTAssertEqual(SubagentStatus.completed.label, "Done")
        XCTAssertEqual(SubagentStatus.cancelled.label, "Cancelled")
        XCTAssertEqual(SubagentStatus.awaitingApproval.label, "Needs approval")
        XCTAssertTrue(ToolDefinition.subagentsUpdate.parametersJSON.contains(#""subagents""#))
        XCTAssertTrue(ToolDefinition.subagentsUpdate.parametersJSON.contains(#""groupPath""#))
        XCTAssertTrue(ToolDefinition.subagentsUpdate.parametersJSON.contains(#""approvalGate""#))
        XCTAssertTrue(ToolDefinition.subagentsUpdate.parametersJSON.contains("awaitingApproval"))
        XCTAssertTrue(ToolDefinition.subagentsUpdate.parametersJSON.contains("blocked"))
        XCTAssertTrue(ToolDefinition.subagentsUpdate.parametersJSON.contains("cancelled"))
    }

    func testLegacySubagentProgressItemDecodesWithoutTranscript() throws {
        let legacyJSON = #"{"name":"Explorer","role":"Inspect files","status":"completed"}"#

        let decoded = try JSONHelpers.decode(SubagentProgressItem.self, from: legacyJSON)

        XCTAssertTrue(decoded.transcript.isEmpty)
        XCTAssertNil(decoded.approvalGate)
    }

    func testSubagentRunToolRequiresExecutableWorkerPlan() {
        let definition = ToolDefinition.subagentsRun

        XCTAssertEqual(definition.name, "host.subagents.run")
        XCTAssertEqual(definition.host, .local)
        XCTAssertEqual(definition.risk, .read)
        XCTAssertTrue(definition.description.contains("Run real delegated agents"))
        XCTAssertTrue(definition.parametersJSON.contains(#""objective""#))
        XCTAssertTrue(definition.parametersJSON.contains(#""workers""#))
        XCTAssertTrue(definition.parametersJSON.contains(#""dependsOn""#))
        XCTAssertTrue(definition.parametersJSON.contains(#""maxConcurrentWorkers""#))
    }

    func testCoreToolDefinitionSchemasAreValidJSONObjects() throws {
        let definitions: [ToolDefinition] = [
            .planUpdate,
            .handoffUpdate,
            .subagentsRun,
            .subagentsUpdate,
            .browserInspect,
            .browserOpen,
            .browserClick,
            .browserType,
            .browserScript,
            .memoryRemember
        ]

        for definition in definitions {
            let data = try XCTUnwrap(definition.parametersJSON.data(using: .utf8))
            XCTAssertTrue(
                try JSONSerialization.jsonObject(with: data) is [String: Any],
                "\(definition.name) parametersJSON should be a JSON object schema."
            )
        }
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
}
