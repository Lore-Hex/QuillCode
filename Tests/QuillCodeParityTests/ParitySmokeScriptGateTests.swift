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
        XCTAssertTrue(script.contains("workspace-read-natural"))
        XCTAssertTrue(script.contains("What is in live-smoke.txt?"))
        XCTAssertTrue(script.contains("negative-shell-action"))
        XCTAssertTrue(script.contains("negative-file-write"))
        XCTAssertTrue(script.contains("negative-download"))
        XCTAssertTrue(script.contains("quillcode_live_forbidden_shell"))
        XCTAssertTrue(script.contains("forbidden-live.txt"))
        XCTAssertTrue(script.contains("downloads/forbidden-live.html"))
        XCTAssertTrue(script.contains("PASSIVE_ACTION_PATTERN="))
        XCTAssertTrue(script.contains("I will"))
        XCTAssertTrue(script.contains("execute|inspect|list|show|review|read|fetch|save"))
        XCTAssertTrue(script.contains("--arg passiveActionPattern \"$PASSIVE_ACTION_PATTERN\""))
        XCTAssertTrue(script.contains("test($passiveActionPattern; \"i\")"))
        XCTAssertTrue(script.contains("assert_saved_transcripts_match_live_smoke_expectations 17 3"))
        XCTAssertTrue(script.contains("negative_transcript_ok"))
        XCTAssertTrue(script.contains("(queued_calls | length) == 0"))
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

    func testRealWorldSmokeRequiresDeterministicPlaywrightEvidenceWhenPlaywrightIsRequired() throws {
        let script = try Self.scriptText(named: "real-world-smoke.sh")

        XCTAssertTrue(script.contains("assert_deterministic_real_world_evidence"))
        XCTAssertTrue(script.contains("validate-playwright-real-world-manifest.py"))
        XCTAssertTrue(script.contains("playwright-real-world-actions-manifest.json"))
        XCTAssertTrue(script.contains("deterministic-smoke-manifest.json"))
        XCTAssertTrue(script.contains("\"realWorldActions\""))
        XCTAssertTrue(script.contains("DETERMINISTIC_STATUS=\"validating-real-world-evidence\""))
        XCTAssertTrue(script.contains("deterministic real-world evidence validation failed"))
        XCTAssertTrue(script.contains("steps should be an object"))
        XCTAssertTrue(script.contains("steps.playwright should be an object"))
        XCTAssertTrue(script.contains("steps.playwright.realWorldActions should be an object"))
        XCTAssertTrue(script.contains("scenarioCount should be at least 8"))
        XCTAssertTrue(script.contains("promptCount should be at least 17"))
        XCTAssertTrue(script.contains("regressionGuardCount should be at least 24"))
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
        XCTAssertTrue(script.contains("PASSIVE_ACTION_PATTERN="))
        XCTAssertTrue(script.contains("I will"))
        XCTAssertTrue(script.contains("execute|inspect|list|show|review|read|fetch|save"))
        XCTAssertTrue(script.contains("grep -Eqi \"$PASSIVE_ACTION_PATTERN\""))
        XCTAssertTrue(script.contains("forbidden.txt despite explicit negative intent"))
        XCTAssertTrue(script.contains("forbidden.html despite explicit negative intent"))
    }

    func testDeterministicSmokeCoversNaturalGitReadPrompts() throws {
        let script = try Self.scriptText(named: "smoke.sh")

        XCTAssertTrue(script.contains("CLI_GIT_READ_STATUS=\"not-run\""))
        XCTAssertTrue(script.contains("\"cliGitRead\""))
        XCTAssertTrue(script.contains("prepare_git_workspace()"))
        XCTAssertTrue(script.contains("tracked.txt"))
        XCTAssertTrue(script.contains("Please check git status."))
        XCTAssertTrue(script.contains("what changed?"))
        XCTAssertTrue(script.contains("Git status:"))
        XCTAssertTrue(script.contains("Git diff:"))
        XCTAssertTrue(script.contains("+after"))
    }

    func testDeterministicSmokeCoversNaturalFileReadPrompts() throws {
        let script = try Self.scriptText(named: "smoke.sh")

        XCTAssertTrue(script.contains("CLI_FILE_READ_STATUS=\"not-run\""))
        XCTAssertTrue(script.contains("\"cliFileRead\""))
        XCTAssertTrue(script.contains("QuillCode smoke README"))
        XCTAssertTrue(script.contains("What is in README.md?"))
        XCTAssertTrue(script.contains("Contents of `README.md`"))
    }

    func testPlaywrightRealWorldManifestValidatorGuardsReleaseEvidence() throws {
        let script = try Self.scriptText(named: "smoke.sh")
        let validator = try Self.scriptText(named: "validate-playwright-real-world-manifest.py")

        XCTAssertTrue(script.contains("validate-playwright-real-world-manifest.py"))
        XCTAssertTrue(validator.contains("REQUIRED_SCENARIOS"))
        XCTAssertTrue(validator.contains("MIN_PROMPT_COUNT = 17"))
        XCTAssertTrue(validator.contains("MIN_REGRESSION_GUARD_COUNT = 24"))
        XCTAssertTrue(validator.contains("runs natural shell requests immediately with nonempty arguments"))
        XCTAssertTrue(validator.contains("writes requested file content immediately without a confirmation loop"))
        XCTAssertTrue(validator.contains("reads requested file contents immediately with the structured file tool"))
        XCTAssertTrue(validator.contains("searches workspace text with the structured file search tool"))
        XCTAssertTrue(validator.contains("answers device diagnostic prompts with concrete shell actions"))
        XCTAssertTrue(validator.contains("downloads requested domains with a bounded concrete shell action"))
        XCTAssertTrue(validator.contains("answers natural git read requests with structured git tools"))
        XCTAssertTrue(validator.contains("respects explicit negative action prompts without tool cards or side effects"))
        XCTAssertTrue(validator.contains("Please check git status."))
        XCTAssertTrue(validator.contains("what changed?"))
        XCTAssertTrue(validator.contains("What is in README.md?"))
        XCTAssertTrue(validator.contains("Where is AgentRunner defined?"))
        XCTAssertTrue(validator.contains("shell arguments are never {}"))
        XCTAssertTrue(validator.contains("assistant does not answer with passive promises"))
        XCTAssertTrue(validator.contains("file read uses host.file.read instead of shell cat fallback"))
        XCTAssertTrue(validator.contains("file search uses host.file.search instead of shell grep fallback"))
        XCTAssertTrue(validator.contains("safety review does not block clear user intent"))
        XCTAssertTrue(validator.contains("git status uses host.git.status instead of shell fallback"))
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
        XCTAssertTrue(script.contains("ACCESSIBILITY_FRAMES_MANIFEST=\"$SMOKE_ROOT/packaged-accessibility-frames.json\""))
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
        XCTAssertTrue(script.contains("packaged-accessibility-frames.json"))
        XCTAssertTrue(script.contains("accessibility_frames_manifest=packaged-accessibility-frames.json"))
        XCTAssertTrue(script.contains(" frames \\"))
        XCTAssertTrue(script.contains("$WINDOW_REPORT_PATH"))
        XCTAssertTrue(script.contains("$WINDOW_SCREENSHOT_PATH"))
        XCTAssertTrue(script.contains("--click-probe-manifest \"$CLICK_PROBE_MANIFEST\""))
        XCTAssertTrue(script.contains("--manifest \"$ACCESSIBILITY_FRAMES_MANIFEST\""))
        XCTAssertTrue(validator.contains("normalized_probe_contracts"))
        XCTAssertTrue(validator.contains("click_probes = targets.get(\"clickProbes\")"))
        XCTAssertTrue(validator.contains("samplePoints"))
        XCTAssertTrue(validator.contains("allowsNestedInteractiveChildren"))
        XCTAssertTrue(validator.contains("requiresUnblockedInterior"))
        XCTAssertTrue(validator.contains("hitTestAvailable"))
        XCTAssertTrue(validator.contains("hitTestError"))
        XCTAssertTrue(validator.contains("hitTestIdentifier"))
        XCTAssertTrue(validator.contains("hitTestRole"))
        XCTAssertTrue(validator.contains("hitTestLabel"))
        XCTAssertTrue(validator.contains("hitTestAncestorIdentifiers"))
        XCTAssertTrue(validator.contains("hitTestMatchesTarget"))
        XCTAssertTrue(validator.contains("Accessibility sample point"))
        XCTAssertTrue(validator.contains("nested-child policy drift"))
        XCTAssertTrue(validator.contains("interior-blocking policy drift"))
        XCTAssertTrue(validator.contains("launchServicesMatchesDirect"))
        XCTAssertTrue(validator.contains("direct_probe_contracts != launch_services_probe_contracts"))
        XCTAssertTrue(validator.contains("missingFromLaunch"))
        XCTAssertTrue(validator.contains("driftingContracts"))
        XCTAssertTrue(validator.contains("write_accessibility_readiness_manifest"))
        XCTAssertTrue(validator.contains("report-ready-for-accessibility-frame-sampling"))
        XCTAssertTrue(validator.contains("write_accessibility_frames_manifest"))
        XCTAssertTrue(validator.contains("live-accessibility-frame-sampled"))
        XCTAssertTrue(validator.contains("REQUIRED_LIVE_ACCESSIBILITY_CONTRACT_IDS"))
        XCTAssertTrue(validator.contains("window_command_contract_ids"))
        XCTAssertTrue(validator.contains("\"windowCommandContractIDs\""))
        XCTAssertTrue(validator.contains("\"windowCommandContractCount\""))
        XCTAssertTrue(validator.contains("packaged click-probe manifest is missing window command contracts"))
        XCTAssertTrue(validator.contains("\"accessibilityFrameSamples\""))
        XCTAssertTrue(validator.contains("liveAccessibilitySampling"))
        XCTAssertTrue(validator.contains("\"frame-sampled\""))
        XCTAssertTrue(validator.contains("\"unresolvedRequiredContractIDs\""))
        XCTAssertTrue(validator.contains("\"sampleCount\""))
        XCTAssertTrue(validator.contains("validate_packaged_window_report"))
        XCTAssertTrue(validator.contains("REQUIRED_WINDOW_COMMAND_IDS"))
        XCTAssertTrue(validator.contains("REQUIRED_WINDOW_STARTER_ACTION_IDS"))
        XCTAssertTrue(validator.contains("MINIMUM_WINDOW_SCREENSHOT_BYTES"))
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
        let windowReport = temporaryDirectory.appendingPathComponent("window-report.json")
        let windowScreenshot = temporaryDirectory.appendingPathComponent("window.png")
        try Self.minimalClickProbeReport.write(to: report, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: directDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: launchServicesDirectory, withIntermediateDirectories: true)
        try Self.minimalClickProbeReport.write(to: directReport, atomically: true, encoding: .utf8)
        try Self.minimalClickProbeReport.write(to: launchServicesReport, atomically: true, encoding: .utf8)
        try Self.minimalPackagedWindowReport.write(to: windowReport, atomically: true, encoding: .utf8)
        try Data(repeating: 0, count: 4096).write(to: windowScreenshot)

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
        XCTAssertEqual(probePolicy["collisionScope"] as? String, "composer:composer")
        XCTAssertEqual(probePolicy["allowsNestedInteractiveChildren"] as? Bool, false)
        XCTAssertEqual(probePolicy["requiresUnblockedInterior"] as? Bool, true)
        XCTAssertEqual(manifestObject["collisionScopes"] as? [String], ["composer:composer"])
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
        XCTAssertEqual(readinessPolicy["collisionScope"] as? String, "composer:composer")
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

        let windowResult = try Self.runPython(validator, arguments: [
            "window",
            windowReport.path,
            windowScreenshot.path
        ])
        XCTAssertEqual(windowResult.exitCode, 0, windowResult.output)
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
                "collisionScope": "composer:composer",
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
                "collisionScope": "composer:composer",
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

    private static var minimalPackagedWindowReport: String {
        let commandIDs = minimalPackagedWindowCommandIDs
            .map { #"              "\#($0)""# }
            .joined(separator: ",\n")
        let surfaceContracts = ([minimalComposerSurfaceContractJSON] + minimalPackagedWindowCommandIDs.map(commandSurfaceContractJSON))
            .joined(separator: ",\n")
        let clickProbes = ([minimalComposerClickProbeJSON] + minimalPackagedWindowCommandIDs.map(commandClickProbeJSON))
            .joined(separator: ",\n")

        return """
        {
          "ok": true,
          "appName": "QuillCode",
          "bundleIdentifier": "co.lorehex.QuillCode",
          "windowTitle": "QuillCode",
          "screenshotPath": "window.png",
          "image": {
            "width": 1280,
            "height": 900,
            "distinctColorBuckets": 16
          },
          "surface": {
            "appName": "QuillCode",
            "primaryTitle": "run whoami",
            "modelLabel": "Nike 1.0",
            "modeLabel": "Auto",
            "agentStatus": "TrustedRouter signed in",
            "composerPlaceholder": "Message QuillCode",
            "composerCanSend": false,
            "sidebarTitle": "Chats",
            "commandIDs": [
        \(commandIDs)
            ],
            "starterActionIDs": [
              "review-changes",
              "run-tests",
              "explain-project"
            ]
          },
          "nativeHitTargets": {
            "surfaceContracts": [
        \(surfaceContracts)
            ],
            "clickProbes": [
        \(clickProbes)
            ],
            "missingClickProbeContractIDs": [],
            "clickProbeValidationIssues": []
          }
        }
        """
    }

    private static let minimalPackagedWindowCommandIDs = [
        "new-chat",
        "command-palette",
        "keyboard-shortcuts",
        "settings",
        "toggle-terminal",
        "toggle-browser",
        "stop-all",
        "disconnect-all"
    ]

    private static var minimalComposerSurfaceContractJSON: String {
        """
              {
                "id": "composer.send",
                "testID": "quillcode-send-button",
                "collisionScope": "composer:composer",
                "kind": "icon",
                "action": "press",
                "allowsNestedInteractiveChildren": false,
                "requiresUnblockedInterior": true
              }
        """
    }

    private static var minimalComposerClickProbeJSON: String {
        """
              {
                "contractID": "composer.send",
                "selectorKind": "test-id",
                "selector": "quillcode-send-button",
                "collisionScope": "composer:composer",
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
        """
    }

    private static func commandSurfaceContractJSON(_ commandID: String) -> String {
        """
              {
                "id": "command.\(commandID)",
                "commandID": "\(commandID)",
                "collisionScope": "command:workspace-chrome",
                "kind": "fullRow",
                "action": "press",
                "allowsNestedInteractiveChildren": false,
                "requiresUnblockedInterior": true
              }
        """
    }

    private static func commandClickProbeJSON(_ commandID: String) -> String {
        """
              {
                "contractID": "command.\(commandID)",
                "selectorKind": "command-id",
                "selector": "\(commandID)",
                "collisionScope": "command:workspace-chrome",
                "kind": "fullRow",
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
        """
    }
}
