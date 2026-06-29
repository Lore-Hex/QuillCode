import XCTest

final class ParitySmokeScriptGateTests: QuillCodeParityTestCase {
    func testLiveTrustedRouterSmokeManifestRecordsSecretFreeRuntimeEvidence() throws {
        let script = try Self.scriptText(named: "live-tr-smoke.sh")

        XCTAssertTrue(script.contains("API_KEY_SOURCE=\"missing\""))
        XCTAssertTrue(script.contains("API_KEY_SOURCE=\"env:QUILLCODE_API_KEY\""))
        XCTAssertTrue(script.contains("API_KEY_SOURCE=\"env:TRUSTEDROUTER_API_KEY\""))
        XCTAssertTrue(script.contains("API_KEY_SOURCE=\"key-file\""))
        XCTAssertTrue(script.contains("elif [[ -s \"$KEY_FILE\" ]]"))
        XCTAssertTrue(script.contains("--arg rawModel \"$RAW_MODEL\""))
        XCTAssertTrue(script.contains("--arg keySource \"$API_KEY_SOURCE\""))
        XCTAssertTrue(script.contains("transport: \"TrustedRouter\""))
        XCTAssertTrue(script.contains("rawModel: $rawModel"))
        XCTAssertTrue(script.contains("normalizedModel: $model"))
        XCTAssertTrue(script.contains("keySource: $keySource"))
        XCTAssertTrue(script.contains("secretFree: true"))
        XCTAssertTrue(script.contains("shell-action-now"))
        XCTAssertTrue(script.contains("quillcode_live_now_smoke"))
        XCTAssertTrue(script.contains("shell-action-polite-bare"))
        XCTAssertTrue(script.contains("quillcode_live_polite_smoke"))
        XCTAssertTrue(script.contains("git-status-polite"))
        XCTAssertTrue(script.contains("workspace-list-natural"))
        XCTAssertTrue(script.contains("workspace-pwd-natural"))
        XCTAssertFalse(
            script.contains("--arg apiKey \"$API_KEY\""),
            "Live smoke manifests must not pass the raw API key into jq."
        )
    }

    func testRealWorldSmokeManifestCarriesLiveRuntimeConfiguration() throws {
        let script = try Self.scriptText(named: "real-world-smoke.sh")

        XCTAssertTrue(script.contains("LIVE_KEY_SOURCE=\"missing\""))
        XCTAssertTrue(script.contains("LIVE_MODEL=\"${QUILLCODE_LIVE_MODEL:-deepseekv4flash}\""))
        XCTAssertTrue(script.contains("LIVE_BASE_URL=\"${QUILLCODE_LIVE_BASE_URL:-https://api.trustedrouter.com/v1}\""))
        XCTAssertTrue(script.contains("live_key_source()"))
        XCTAssertTrue(script.contains("printf 'env:QUILLCODE_API_KEY'"))
        XCTAssertTrue(script.contains("printf 'env:TRUSTEDROUTER_API_KEY'"))
        XCTAssertTrue(script.contains("printf 'key-file'"))
        XCTAssertTrue(script.contains("\"configured\": {"))
        XCTAssertTrue(script.contains("\"transport\": \"TrustedRouter\""))
        XCTAssertTrue(script.contains("\"rawModel\": live_model"))
        XCTAssertTrue(script.contains("\"baseURL\": live_base_url"))
        XCTAssertTrue(script.contains("\"keySource\": live_key_source"))
        XCTAssertTrue(script.contains("\"secretFree\": True"))
        XCTAssertTrue(script.contains("LIVE_KEY_SOURCE=\"$(live_key_source)\""))
        XCTAssertFalse(
            script.contains("QUILLCODE_API_KEY\"") && script.contains("\"apiKey\""),
            "The real-world wrapper should record key source metadata, never raw key material."
        )
    }

    func testDeterministicSmokeCoversExplicitNegativeActionIntent() throws {
        let script = try Self.scriptText(named: "smoke.sh")

        XCTAssertTrue(script.contains("CLI_NEGATIVE_ACTION_STATUS=\"not-run\""))
        XCTAssertTrue(script.contains("\"cliNegativeActions\""))
        XCTAssertTrue(script.contains("Do not run whoami."))
        XCTAssertTrue(script.contains("Do not write"))
        XCTAssertTrue(script.contains("forbidden.txt"))
        XCTAssertTrue(script.contains("Don't download https://example.com"))
        XCTAssertTrue(script.contains("downloads/forbidden.html"))
        XCTAssertTrue(script.contains("forbidden.txt despite explicit negative intent"))
        XCTAssertTrue(script.contains("forbidden.html despite explicit negative intent"))
    }

    func testRealWorldSmokeWorkflowRunsReleaseCandidateWrapperWithArtifacts() throws {
        let workflow = try Self.workflowText(named: "real-world-smoke.yml")

        XCTAssertTrue(workflow.contains("name: Real World Smoke"))
        XCTAssertTrue(workflow.contains("workflow_dispatch:"))
        XCTAssertTrue(workflow.contains("require_live:"))
        XCTAssertTrue(workflow.contains("default: true"))
        XCTAssertTrue(workflow.contains("schedule:"))
        XCTAssertTrue(workflow.contains("QUILLCODE_API_KEY: ${{ secrets.QUILLCODE_LIVE_API_KEY }}"))
        XCTAssertTrue(workflow.contains("QUILLCODE_LIVE_MODEL: ${{ inputs.model || 'deepseekv4flash' }}"))
        XCTAssertTrue(workflow.contains("QUILLCODE_REQUIRE_LIVE_SMOKE: ${{ inputs.require_live && '1' || '0' }}"))
        XCTAssertTrue(workflow.contains("QUILLCODE_REAL_WORLD_REQUIRE_PLAYWRIGHT: \"1\""))
        XCTAssertTrue(workflow.contains("QUILLCODE_REAL_WORLD_SMOKE_ARTIFACT_DIR:"))
        XCTAssertTrue(workflow.contains("npm ci"))
        XCTAssertTrue(workflow.contains("npx playwright install chromium"))
        XCTAssertTrue(workflow.contains("./scripts/real-world-smoke.sh"))
        XCTAssertTrue(workflow.contains("actions/upload-artifact@v4"))
        XCTAssertTrue(workflow.contains("retention-days: 30"))
        XCTAssertFalse(
            workflow.contains("live-tr-smoke.sh"),
            "Release-candidate workflow should run the real-world wrapper, not bypass deterministic smoke."
        )
    }

    func testPackagedMacOSSmokeComparesDirectAndLaunchServicesClickProbes() throws {
        let script = try Self.scriptText(named: "packaged-macos-smoke.sh")
        let validator = try Self.scriptText(named: "native-click-probe-contracts.py")

        XCTAssertTrue(script.contains("DIRECT_SMOKE_ARTIFACT_DIR=\"$SMOKE_ROOT/direct-executable\""))
        XCTAssertTrue(script.contains("LAUNCH_SERVICES_SMOKE_ARTIFACT_DIR=\"$SMOKE_ROOT/launch-services\""))
        XCTAssertTrue(script.contains("CLICK_PROBE_MANIFEST=\"$SMOKE_ROOT/packaged-click-probes.json\""))
        XCTAssertTrue(script.contains("ACCESSIBILITY_READINESS_MANIFEST=\"$SMOKE_ROOT/packaged-accessibility-readiness.json\""))
        XCTAssertTrue(script.contains("QUILLCODE_NATIVE_DESKTOP_SMOKE_ARTIFACT_DIR=\"$DIRECT_SMOKE_ARTIFACT_DIR\""))
        XCTAssertTrue(script.contains("QUILLCODE_NATIVE_DESKTOP_SMOKE_ARTIFACT_DIR=\"$LAUNCH_SERVICES_SMOKE_ARTIFACT_DIR\""))
        XCTAssertTrue(script.contains("scripts/native-click-probe-contracts.py"))
        XCTAssertTrue(script.contains(" compare \\"))
        XCTAssertTrue(script.contains("--manifest \"$CLICK_PROBE_MANIFEST\""))
        XCTAssertTrue(script.contains(" readiness \\"))
        XCTAssertTrue(script.contains("--manifest \"$ACCESSIBILITY_READINESS_MANIFEST\""))
        XCTAssertTrue(script.contains("packaged-click-probes.json"))
        XCTAssertTrue(script.contains("packaged-accessibility-readiness.json"))
        XCTAssertTrue(script.contains("accessibility_readiness_manifest=packaged-accessibility-readiness.json"))
        XCTAssertTrue(validator.contains("normalized_probe_contracts"))
        XCTAssertTrue(validator.contains("click_probes = targets.get(\"clickProbes\")"))
        XCTAssertTrue(validator.contains("samplePoints"))
        XCTAssertTrue(validator.contains("allowsNestedInteractiveChildren"))
        XCTAssertTrue(validator.contains("requiresUnblockedInterior"))
        XCTAssertTrue(validator.contains("nested-child policy drift"))
        XCTAssertTrue(validator.contains("interior-blocking policy drift"))
        XCTAssertTrue(validator.contains("launchServicesMatchesDirect"))
        XCTAssertTrue(validator.contains("direct_probe_contracts != launch_services_probe_contracts"))
        XCTAssertTrue(validator.contains("missingFromLaunch"))
        XCTAssertTrue(validator.contains("driftingContracts"))
        XCTAssertTrue(validator.contains("write_accessibility_readiness_manifest"))
        XCTAssertTrue(validator.contains("report-ready-for-accessibility-frame-sampling"))
        XCTAssertTrue(validator.contains("liveAccessibilitySampling"))
    }

    func testNativeClickProbeValidatorCLIValidatesAndWritesPackagedManifests() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-click-probe-validator-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let report = temporaryDirectory.appendingPathComponent("report.json")
        let directDirectory = temporaryDirectory.appendingPathComponent("direct-executable")
        let launchServicesDirectory = temporaryDirectory.appendingPathComponent("launch-services")
        let directReport = directDirectory.appendingPathComponent("report.json")
        let launchServicesReport = launchServicesDirectory.appendingPathComponent("report.json")
        let manifest = temporaryDirectory.appendingPathComponent("packaged-click-probes.json")
        let readiness = temporaryDirectory.appendingPathComponent("packaged-accessibility-readiness.json")
        try Self.minimalClickProbeReport.write(to: report, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: directDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: launchServicesDirectory, withIntermediateDirectories: true)
        try Self.minimalClickProbeReport.write(to: directReport, atomically: true, encoding: .utf8)
        try Self.minimalClickProbeReport.write(to: launchServicesReport, atomically: true, encoding: .utf8)

        let validator = Self.packageRoot()
            .appendingPathComponent("scripts")
            .appendingPathComponent("native-click-probe-contracts.py")
        XCTAssertEqual(try Self.runPython(validator, arguments: ["validate", report.path]).exitCode, 0)

        let compare = try Self.runPython(validator, arguments: [
            "compare",
            directReport.path,
            launchServicesReport.path,
            "--manifest",
            manifest.path
        ])
        XCTAssertEqual(compare.exitCode, 0, compare.output)

        let manifestData = try Data(contentsOf: manifest)
        let manifestObject = try XCTUnwrap(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
        XCTAssertEqual(manifestObject["ok"] as? Bool, true)
        XCTAssertEqual(manifestObject["launchServicesMatchesDirect"] as? Bool, true)
        XCTAssertEqual(manifestObject["clickProbeCount"] as? Int, 1)
        let probePolicies = try XCTUnwrap(manifestObject["clickProbePolicies"] as? [[String: Any]])
        let probePolicy = try XCTUnwrap(probePolicies.first)
        XCTAssertEqual(probePolicy["contractID"] as? String, "composer.send")
        XCTAssertEqual(probePolicy["allowsNestedInteractiveChildren"] as? Bool, false)
        XCTAssertEqual(probePolicy["requiresUnblockedInterior"] as? Bool, true)
        XCTAssertEqual(manifestObject["samplePointNames"] as? [String], [
            "bottom-interior",
            "center",
            "leading-interior",
            "top-interior",
            "trailing-interior"
        ])

        let readinessResult = try Self.runPython(validator, arguments: [
            "readiness",
            temporaryDirectory.path,
            "--manifest",
            readiness.path
        ])
        XCTAssertEqual(readinessResult.exitCode, 0, readinessResult.output)

        let readinessData = try Data(contentsOf: readiness)
        let readinessObject = try XCTUnwrap(JSONSerialization.jsonObject(with: readinessData) as? [String: Any])
        XCTAssertEqual(readinessObject["ok"] as? Bool, true)
        XCTAssertEqual(readinessObject["stage"] as? String, "report-ready-for-accessibility-frame-sampling")
        XCTAssertEqual(readinessObject["liveAccessibilitySampling"] as? String, "not-run")
        XCTAssertEqual(readinessObject["clickProbeManifest"] as? String, "packaged-click-probes.json")
        XCTAssertEqual(readinessObject["directReport"] as? String, "direct-executable/report.json")
        XCTAssertEqual(readinessObject["launchServicesReport"] as? String, "launch-services/report.json")
        XCTAssertEqual(readinessObject["launchServicesMatchesDirect"] as? Bool, true)
        XCTAssertEqual(readinessObject["clickProbeCount"] as? Int, 1)
        XCTAssertEqual(readinessObject["minimumHitTarget"] as? Int, 44)
        let readinessPolicies = try XCTUnwrap(readinessObject["clickProbePolicies"] as? [[String: Any]])
        let readinessPolicy = try XCTUnwrap(readinessPolicies.first)
        XCTAssertEqual(readinessPolicy["contractID"] as? String, "composer.send")
        XCTAssertEqual(readinessPolicy["allowsNestedInteractiveChildren"] as? Bool, false)
        XCTAssertEqual(readinessPolicy["requiresUnblockedInterior"] as? Bool, true)
        XCTAssertEqual(readinessObject["requiredSamplePointNames"] as? [String], [
            "bottom-interior",
            "center",
            "leading-interior",
            "top-interior",
            "trailing-interior"
        ])
        XCTAssertEqual(readinessObject["contractIDs"] as? [String], ["composer.send"])
    }

    private struct ScriptResult {
        let exitCode: Int32
        let output: String
    }

    private static func runPython(_ script: URL, arguments: [String]) throws -> ScriptResult {
        let outputPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", script.path] + arguments
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return ScriptResult(exitCode: process.terminationStatus, output: output)
    }

    private static func scriptText(named fileName: String) throws -> String {
        let file = packageRoot()
            .appendingPathComponent("scripts")
            .appendingPathComponent(fileName)
        return try String(contentsOf: file, encoding: .utf8)
    }

    private static func workflowText(named fileName: String) throws -> String {
        let file = packageRoot()
            .appendingPathComponent(".github/workflows")
            .appendingPathComponent(fileName)
        return try String(contentsOf: file, encoding: .utf8)
    }

    private static var minimalClickProbeReport: String {
        """
        {
          "nativeHitTargets": {
            "surfaceContracts": [
              {
                "id": "composer.send",
                "testID": "quillcode-send-button",
                "kind": "icon",
                "action": "press",
                "allowsNestedInteractiveChildren": false,
                "requiresUnblockedInterior": true
              }
            ],
            "clickProbes": [
              {
                "contractID": "composer.send",
                "selectorKind": "test-id",
                "selector": "quillcode-send-button",
                "kind": "icon",
                "action": "press",
                "allowsNestedInteractiveChildren": false,
                "requiresUnblockedInterior": true,
                "requiredMinWidth": 44,
                "requiredMinHeight": 44,
                "samplePoints": [
                  {"name": "center", "x": 0.5, "y": 0.5},
                  {"name": "leading-interior", "x": 0.18, "y": 0.5},
                  {"name": "trailing-interior", "x": 0.82, "y": 0.5},
                  {"name": "top-interior", "x": 0.5, "y": 0.18},
                  {"name": "bottom-interior", "x": 0.5, "y": 0.82}
                ]
              }
            ],
            "missingClickProbeContractIDs": [],
            "clickProbeValidationIssues": []
          }
        }
        """
    }
}
