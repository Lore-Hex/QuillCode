import XCTest

final class ParityPackagedClickProbeSmokeGateTests: QuillCodeParityTestCase {
    func testPackagedMacOSSmokeComparesDirectAndLaunchServicesClickProbes() throws {
        let script = try Self.scriptText(named: "packaged-macos-smoke.sh")
        let validator = try Self.nativeClickProbeValidatorText()

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
        XCTAssertTrue(validator.contains("requiresTactileFeedback"))
        XCTAssertTrue(validator.contains("allowsTextSelection"))
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
        XCTAssertTrue(validator.contains("accessibilityActivation"))
        XCTAssertTrue(validator.contains("liveAccessibilityActivation"))
        XCTAssertTrue(validator.contains("\"ax-press-sampled\""))
        XCTAssertTrue(validator.contains("REQUIRED_LIVE_ACCESSIBILITY_ACTIVATION_CONTRACT_IDS"))
        XCTAssertTrue(validator.contains("activationCheckSummaries"))
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
        let accessibilityFrameReport = temporaryDirectory.appendingPathComponent("window-accessibility-report.json")
        let blockedAccessibilityFrameReport = temporaryDirectory.appendingPathComponent("window-accessibility-blocked-report.json")
        let shallowSearchActivationReport = temporaryDirectory
            .appendingPathComponent("window-accessibility-shallow-search-report.json")
        let shallowNewChatActivationReport = temporaryDirectory
            .appendingPathComponent("window-accessibility-shallow-new-chat-report.json")
        let shallowModelPickerActivationReport = temporaryDirectory
            .appendingPathComponent("window-accessibility-shallow-model-picker-report.json")
        let shallowSettingsActivationReport = temporaryDirectory
            .appendingPathComponent("window-accessibility-shallow-settings-report.json")
        let shallowAutomationsActivationReport = temporaryDirectory
            .appendingPathComponent("window-accessibility-shallow-automations-report.json")
        let windowScreenshot = temporaryDirectory.appendingPathComponent("window.png")
        let accessibilityFrames = temporaryDirectory.appendingPathComponent("packaged-accessibility-frames.json")
        let blockedAccessibilityFrames = temporaryDirectory.appendingPathComponent("blocked-packaged-accessibility-frames.json")
        let shallowSearchAccessibilityFrames = temporaryDirectory
            .appendingPathComponent("shallow-search-packaged-accessibility-frames.json")
        let shallowNewChatAccessibilityFrames = temporaryDirectory
            .appendingPathComponent("shallow-new-chat-packaged-accessibility-frames.json")
        let shallowModelPickerAccessibilityFrames = temporaryDirectory
            .appendingPathComponent("shallow-model-picker-packaged-accessibility-frames.json")
        let shallowSettingsAccessibilityFrames = temporaryDirectory
            .appendingPathComponent("shallow-settings-packaged-accessibility-frames.json")
        let shallowAutomationsAccessibilityFrames = temporaryDirectory
            .appendingPathComponent("shallow-automations-packaged-accessibility-frames.json")
        try Self.minimalClickProbeReport.write(to: report, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: directDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: launchServicesDirectory, withIntermediateDirectories: true)
        try Self.minimalClickProbeReport.write(to: directReport, atomically: true, encoding: .utf8)
        try Self.minimalClickProbeReport.write(to: launchServicesReport, atomically: true, encoding: .utf8)
        try Self.minimalPackagedWindowReport.write(to: windowReport, atomically: true, encoding: .utf8)
        try Self.minimalPackagedWindowAccessibilityFrameReport()
            .write(to: accessibilityFrameReport, atomically: true, encoding: .utf8)
        try Self.minimalPackagedWindowAccessibilityFrameReport(firstSampleHitTestMatchesTarget: false)
            .write(to: blockedAccessibilityFrameReport, atomically: true, encoding: .utf8)
        try Self.minimalPackagedWindowAccessibilityFrameReport()
            .replacingOccurrences(
                of: "quillcode-search-input focused and accepted reversible AXValue text entry",
                with: "AXPress changed observable controller state"
            )
            .write(to: shallowSearchActivationReport, atomically: true, encoding: .utf8)
        try Self.minimalPackagedWindowAccessibilityFrameReport()
            .replacingOccurrences(
                of: "created exactly one selected chat and quillcode-composer-input focused with reversible AXValue text entry",
                with: "AXPress changed observable controller state"
            )
            .write(to: shallowNewChatActivationReport, atomically: true, encoding: .utf8)
        try Self.minimalPackagedWindowAccessibilityFrameReport()
            .replacingOccurrences(
                of: "quillcode-model-picker-search focused, accepted reversible AXValue text entry, and surfaced the Prometheus 1.0 model option",
                with: "AXPress changed observable controller state"
            )
            .write(to: shallowModelPickerActivationReport, atomically: true, encoding: .utf8)
        try Self.minimalPackagedWindowAccessibilityFrameReport()
            .replacingOccurrences(
                of: "rendered Settings with its notifications control and dismissed through quillcode-settings-close with AXPress",
                with: "AXPress changed observable controller state"
            )
            .write(to: shallowSettingsActivationReport, atomically: true, encoding: .utf8)
        try Self.minimalPackagedWindowAccessibilityFrameReport()
            .replacingOccurrences(
                of: "rendered Automations with its Create control and dismissed through quillcode-automations-close with AXPress",
                with: "AXPress changed observable controller state"
            )
            .write(to: shallowAutomationsActivationReport, atomically: true, encoding: .utf8)
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
        XCTAssertEqual(probePolicy["requiresTactileFeedback"] as? Bool, true)
        XCTAssertEqual(probePolicy["allowsTextSelection"] as? Bool, false)
        XCTAssertEqual(probePolicy["requiredPeerClearance"] as? Double, 8)
        XCTAssertEqual(manifestObject["minimumTargetClearance"] as? Int, 8)
        XCTAssertEqual(manifestObject["collisionScopes"] as? [String], ["composer:composer"])
        XCTAssertEqual(manifestObject["samplePointNames"] as? [String], [
            "bottom-edge",
            "bottom-interior",
            "center",
            "leading-edge",
            "leading-interior",
            "top-edge",
            "top-interior",
            "trailing-edge",
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
        XCTAssertEqual(readinessObject["minimumHitTarget"] as? Int, 40)
        XCTAssertEqual(readinessObject["minimumTargetClearance"] as? Int, 8)
        let readinessPolicies = try XCTUnwrap(readinessObject["clickProbePolicies"] as? [[String: Any]])
        let readinessPolicy = try XCTUnwrap(readinessPolicies.first)
        XCTAssertEqual(readinessPolicy["contractID"] as? String, "composer.send")
        XCTAssertEqual(readinessPolicy["collisionScope"] as? String, "composer:composer")
        XCTAssertEqual(readinessPolicy["allowsNestedInteractiveChildren"] as? Bool, false)
        XCTAssertEqual(readinessPolicy["requiresUnblockedInterior"] as? Bool, true)
        XCTAssertEqual(readinessPolicy["requiresTactileFeedback"] as? Bool, true)
        XCTAssertEqual(readinessPolicy["allowsTextSelection"] as? Bool, false)
        XCTAssertEqual(readinessPolicy["requiredPeerClearance"] as? Double, 8)
        XCTAssertEqual(readinessObject["requiredSamplePointNames"] as? [String], [
            "bottom-edge",
            "bottom-interior",
            "center",
            "leading-edge",
            "leading-interior",
            "top-edge",
            "top-interior",
            "trailing-edge",
            "trailing-interior"
        ])
        XCTAssertEqual(readinessObject["contractIDs"] as? [String], ["composer.send"])

        let windowResult = try Self.runPython(validator, arguments: [
            "window",
            windowReport.path,
            windowScreenshot.path
        ])
        XCTAssertEqual(windowResult.exitCode, 0, windowResult.output)

        let framesResult = try Self.runPython(validator, arguments: [
            "frames",
            accessibilityFrameReport.path,
            windowScreenshot.path,
            "--manifest",
            accessibilityFrames.path
        ])
        XCTAssertEqual(framesResult.exitCode, 0, framesResult.output)

        let framesData = try Data(contentsOf: accessibilityFrames)
        let framesObject = try XCTUnwrap(JSONSerialization.jsonObject(with: framesData) as? [String: Any])
        XCTAssertEqual(framesObject["ok"] as? Bool, true)
        XCTAssertEqual(framesObject["stage"] as? String, "live-accessibility-frame-sampled")
        XCTAssertEqual(framesObject["liveAccessibilitySampling"] as? String, "frame-sampled")
        XCTAssertEqual(framesObject["sampleCount"] as? Int, Self.requiredLiveAccessibilityContractIDs.count)
        XCTAssertEqual(framesObject["requiredContractIDs"] as? [String], Self.requiredLiveAccessibilityContractIDs)
        XCTAssertEqual(framesObject["sampledContractIDs"] as? [String], Self.requiredLiveAccessibilityContractIDs)
        XCTAssertEqual(framesObject["liveAccessibilityActivation"] as? String, "ax-press-sampled")
        XCTAssertEqual(
            framesObject["activationRequiredContractIDs"] as? [String],
            Self.requiredLiveAccessibilityActivationContractIDs
        )
        XCTAssertEqual(
            framesObject["activatedContractIDs"] as? [String],
            Self.requiredLiveAccessibilityActivationContractIDs
        )
        XCTAssertEqual(
            framesObject["activationCheckCount"] as? Int,
            Self.requiredLiveAccessibilityActivationContractIDs.count
        )

        let blockedFramesResult = try Self.runPython(validator, arguments: [
            "frames",
            blockedAccessibilityFrameReport.path,
            windowScreenshot.path,
            "--manifest",
            blockedAccessibilityFrames.path
        ])
        XCTAssertNotEqual(blockedFramesResult.exitCode, 0)
        XCTAssertTrue(
            blockedFramesResult.output.contains("hit 'quillcode-blocker' instead of the target"),
            blockedFramesResult.output
        )

        let shallowSearchResult = try Self.runPython(validator, arguments: [
            "frames",
            shallowSearchActivationReport.path,
            windowScreenshot.path,
            "--manifest",
            shallowSearchAccessibilityFrames.path
        ])
        XCTAssertNotEqual(shallowSearchResult.exitCode, 0)
        XCTAssertTrue(
            shallowSearchResult.output.contains("command.search does not prove focused AXValue text entry"),
            shallowSearchResult.output
        )

        let shallowNewChatResult = try Self.runPython(validator, arguments: [
            "frames",
            shallowNewChatActivationReport.path,
            windowScreenshot.path,
            "--manifest",
            shallowNewChatAccessibilityFrames.path
        ])
        XCTAssertNotEqual(shallowNewChatResult.exitCode, 0)
        XCTAssertTrue(
            shallowNewChatResult.output.contains(
                "command.new-chat does not prove one selected chat with focused AXValue entry"
            ),
            shallowNewChatResult.output
        )

        let shallowModelPickerResult = try Self.runPython(validator, arguments: [
            "frames",
            shallowModelPickerActivationReport.path,
            windowScreenshot.path,
            "--manifest",
            shallowModelPickerAccessibilityFrames.path
        ])
        XCTAssertNotEqual(shallowModelPickerResult.exitCode, 0)
        XCTAssertTrue(
            shallowModelPickerResult.output.contains(
                "composer.model-picker does not prove focused catalog search"
            ),
            shallowModelPickerResult.output
        )

        let shallowSettingsResult = try Self.runPython(validator, arguments: [
            "frames",
            shallowSettingsActivationReport.path,
            windowScreenshot.path,
            "--manifest",
            shallowSettingsAccessibilityFrames.path
        ])
        XCTAssertNotEqual(shallowSettingsResult.exitCode, 0)
        XCTAssertTrue(
            shallowSettingsResult.output.contains(
                "command.settings does not prove rendered controls and close-button dismissal"
            ),
            shallowSettingsResult.output
        )

        let shallowAutomationsResult = try Self.runPython(validator, arguments: [
            "frames",
            shallowAutomationsActivationReport.path,
            windowScreenshot.path,
            "--manifest",
            shallowAutomationsAccessibilityFrames.path
        ])
        XCTAssertNotEqual(shallowAutomationsResult.exitCode, 0)
        XCTAssertTrue(
            shallowAutomationsResult.output.contains(
                "command.toggle-automations does not prove rendered controls and close-button dismissal"
            ),
            shallowAutomationsResult.output
        )
    }
}
