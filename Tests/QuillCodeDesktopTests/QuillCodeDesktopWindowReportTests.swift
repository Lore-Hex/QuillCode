import ApplicationServices
import AppKit
import Foundation
import XCTest
import QuillCodeApp
import QuillCodeCore
import QuillCodePersistence
import QuillComputerUseKit
@testable import quill_code_desktop

@MainActor
final class QuillCodeDesktopWindowReportTests: XCTestCase {
    func testAccessibilityHierarchySignatureIsOrderIndependentAndFrameSensitive() {
        let application = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        let first = QuillCodeDesktopAccessibilityElementSnapshot(
            element: application,
            identifier: "first",
            role: "AXButton",
            title: "First",
            accessibilityLabel: "",
            help: "",
            value: "",
            isFocused: false,
            frame: CGRect(x: 10, y: 20, width: 100, height: 40),
            ancestorIdentifiers: []
        )
        var moved = first
        moved.frame = CGRect(x: 11, y: 20, width: 100, height: 40)
        let second = QuillCodeDesktopAccessibilityElementSnapshot(
            element: application,
            identifier: "second",
            role: "AXTextField",
            title: "",
            accessibilityLabel: "Search",
            help: "",
            value: "",
            isFocused: true,
            frame: CGRect(x: 20, y: 80, width: 200, height: 30),
            ancestorIdentifiers: []
        )

        let forward = QuillCodeDesktopAccessibilityHierarchySettler.signature(
            for: [first, second]
        )
        let reversed = QuillCodeDesktopAccessibilityHierarchySettler.signature(
            for: [second, first]
        )
        let changed = QuillCodeDesktopAccessibilityHierarchySettler.signature(
            for: [moved, second]
        )

        XCTAssertEqual(forward, reversed)
        XCTAssertNotEqual(forward, changed)
    }

    func testDesktopPerformanceSnapshotCapturesBoundedProcessResources() throws {
        let now = ProcessInfo.processInfo.systemUptime
        let initialSnapshot = try QuillCodeDesktopInitialPerformanceSnapshot.capture(
            launchStartedAtUptime: now - 1.25,
            nowUptime: now
        )
        let firstSweepResources = try QuillCodeDesktopProcessResourceSnapshot.capture()
        let snapshot = try initialSnapshot.completingRepeatedInteractionSweep(
            firstSweepResources: firstSweepResources
        )

        XCTAssertEqual(snapshot.launchReadyMilliseconds, 1_250, accuracy: 0.01)
        XCTAssertGreaterThan(snapshot.residentMemoryBytes, 0)
        XCTAssertGreaterThan(snapshot.threadCount, 0)
        XCTAssertGreaterThan(snapshot.postInteractionResources.residentMemoryBytes, 0)
        XCTAssertGreaterThan(snapshot.postInteractionResources.threadCount, 0)
        XCTAssertGreaterThan(snapshot.repeatedInteractionResources.residentMemoryBytes, 0)
        XCTAssertGreaterThan(snapshot.repeatedInteractionResources.threadCount, 0)
        XCTAssertEqual(
            snapshot.residentMemoryGrowthBytes,
            snapshot.postInteractionResources.residentMemoryBytes - snapshot.residentMemoryBytes
        )
        XCTAssertEqual(
            snapshot.dictionary["measurement"] as? String,
            "initial-live-window"
        )
        XCTAssertEqual(
            snapshot.dictionary["postInteractionMeasurement"] as? String,
            "settled-after-native-interaction-sweep"
        )
        XCTAssertEqual(
            snapshot.dictionary["repeatedInteractionMeasurement"] as? String,
            "settled-after-repeated-native-interaction-sweep"
        )
        XCTAssertEqual(snapshot.dictionary["interactionSweepCount"] as? Int, 2)
        XCTAssertEqual(
            snapshot.repeatedInteractionResidentMemoryGrowthBytes,
            snapshot.repeatedInteractionResources.residentMemoryBytes
                - snapshot.postInteractionResources.residentMemoryBytes
        )
    }

    func testDesktopPerformanceSnapshotRejectsInvalidLaunchTiming() {
        XCTAssertThrowsError(
            try QuillCodeDesktopInitialPerformanceSnapshot.capture(
                launchStartedAtUptime: 2,
                nowUptime: 1
            )
        )
    }

    func testCoworkEvalRequestParsesLongRunOverridesAndIsolatedPaths() throws {
        let request = try XCTUnwrap(QuillCodeDesktopCoworkEvalRequest(arguments: [
            "QuillCode",
            "--cowork-eval",
            "--cowork-eval-home", "/tmp/quill-eval-home",
            "--cowork-eval-workspace", "/tmp/quill-eval-workspace",
            "--cowork-eval-prompt-file", "/tmp/quill-eval-prompt.txt",
            "--cowork-eval-report", "/tmp/quill-eval-report.json",
            "--cowork-eval-screenshot", "/tmp/quill-eval-window.png",
            "--cowork-eval-browser-path", "inputs/browser.html",
            "--cowork-eval-timeout-seconds", "3600",
            "--cowork-eval-model", "z-ai/glm-5.2",
            "--cowork-eval-max-tool-steps", "512",
            "--cowork-eval-run-spend-fuse-usd", "none"
        ]))

        XCTAssertEqual(request.homePath, "/tmp/quill-eval-home")
        XCTAssertEqual(request.workspacePath, "/tmp/quill-eval-workspace")
        XCTAssertEqual(request.promptPath, "/tmp/quill-eval-prompt.txt")
        XCTAssertEqual(request.reportPath, "/tmp/quill-eval-report.json")
        XCTAssertEqual(request.screenshotPath, "/tmp/quill-eval-window.png")
        XCTAssertEqual(request.browserPath, "inputs/browser.html")
        XCTAssertEqual(request.modelID, "z-ai/glm-5.2")
        XCTAssertFalse(request.isConfidential)
        XCTAssertEqual(request.timeoutSeconds, 3_600)
        XCTAssertEqual(request.subagentDelegationBudget, .seconds(600))
        XCTAssertEqual(request.maxToolSteps, 512)
        XCTAssertNil(request.runSpendFuseUSD)
        XCTAssertNil(QuillCodeDesktopCoworkEvalRequest(arguments: ["QuillCode"]))
    }

    func testCoworkEvalReservesParentSynthesisTimeFromBoundedRun() throws {
        let request = try XCTUnwrap(QuillCodeDesktopCoworkEvalRequest(arguments: [
            "QuillCode",
            "--cowork-eval",
            "--cowork-eval-timeout-seconds", "900",
        ]))

        XCTAssertEqual(request.subagentDelegationBudget, .seconds(420))
        XCTAssertEqual(request.boundedRunFinalizationAfterSeconds, 420)
    }

    func testCoworkEvalRequestDefaultsToDeepSeekAndClampsLongRunBounds() throws {
        let request = try XCTUnwrap(QuillCodeDesktopCoworkEvalRequest(arguments: [
            "QuillCode",
            "--cowork-eval",
            "--cowork-eval-timeout-seconds", "999999",
            "--cowork-eval-max-tool-steps", "999999"
        ]))

        XCTAssertEqual(request.modelID, "deepseek/deepseek-v4-flash-0731")
        XCTAssertEqual(request.timeoutSeconds, QuillCodeDesktopCoworkEvalRequest.maximumTimeoutSeconds)
        XCTAssertEqual(request.maxToolSteps, QuillCodeDesktopCoworkEvalRequest.maximumToolSteps)
        XCTAssertEqual(request.runSpendFuseUSD, 1.0)
    }

    func testCoworkEvalConfidentialRequestPinsE2ERoute() throws {
        let request = try XCTUnwrap(QuillCodeDesktopCoworkEvalRequest(arguments: [
            "QuillCode",
            "--cowork-eval",
            "--cowork-eval-confidential",
            "--cowork-eval-model", "deepseek/deepseek-v4-flash-0731",
        ]))

        XCTAssertTrue(request.isConfidential)
        XCTAssertEqual(request.modelID, TrustedRouterDefaults.e2eModel)
    }

    func testCoworkEvalControllerUsesExplicitStateAndWorkspace() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-cowork-eval-root-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let request = try XCTUnwrap(QuillCodeDesktopCoworkEvalRequest(arguments: [
            "QuillCode",
            "--cowork-eval",
            "--cowork-eval-home", root.appendingPathComponent("home").path,
            "--cowork-eval-workspace", root.appendingPathComponent("workspace").path,
            "--cowork-eval-prompt-file", root.appendingPathComponent("prompt.txt").path
        ]))
        let controller = request.makeController(environment: ["QUILLCODE_USE_MOCK_LLM": "1"])

        XCTAssertEqual(controller.bootstrap.paths.home.path, request.homePath)
        XCTAssertEqual(controller.workspaceRoot.path, request.workspacePath)
        XCTAssertTrue(controller.model.root.projects.allSatisfy { $0.path == request.workspacePath })
        XCTAssertTrue(controller.automationNotifier is QuillCodeDesktopCoworkEvalNotifier)
        XCTAssertNil(controller.updateController.configuration)
        controller.updateController.startAutomaticChecks()
        XCTAssertEqual(controller.updateController.state, .idle)
        XCTAssertFalse(controller.updateController.isPresented)
        let config = try ConfigStore(fileURL: controller.bootstrap.paths.configFile).load()
        XCTAssertEqual(config.defaultModel, request.modelID)
        XCTAssertEqual(config.maxToolSteps, request.maxToolSteps)
        XCTAssertEqual(config.runSpendFuseUSD, request.runSpendFuseUSD)
        XCTAssertEqual(
            controller.model.subagentDelegationBudgetOverride,
            request.subagentDelegationBudget
        )
        XCTAssertEqual(
            controller.model.boundedRunFinalizationAfterSecondsOverride,
            request.boundedRunFinalizationAfterSeconds
        )
    }

    func testCoworkEvalWindowRetainsOnePhysicalFallbackWindow() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-cowork-eval-window-test-\(UUID().uuidString)")
        defer {
            QuillCodeDesktopCoworkEvalWindow.releaseFallbackForTesting()
            try? FileManager.default.removeItem(at: root)
        }
        let request = try XCTUnwrap(QuillCodeDesktopCoworkEvalRequest(arguments: [
            "QuillCode",
            "--cowork-eval",
            "--cowork-eval-home", root.appendingPathComponent("home").path,
            "--cowork-eval-workspace", root.appendingPathComponent("workspace").path,
            "--cowork-eval-prompt-file", root.appendingPathComponent("prompt.txt").path,
        ]))
        let controller = request.makeController(environment: ["QUILLCODE_USE_MOCK_LLM": "1"])

        let first = QuillCodeDesktopCoworkEvalWindow.retainFallbackForTesting(
            contentView: NSView(frame: NSRect(x: 0, y: 0, width: 1_280, height: 900))
        )
        let second = try await QuillCodeDesktopCoworkEvalWindow.acquire(
            controller: controller,
            sceneSettleAttempts: 1
        )

        XCTAssertEqual(first.source, .evalFallback)
        XCTAssertEqual(second.source, .evalFallback)
        XCTAssertTrue(first.window === second.window)
        XCTAssertTrue(first.window.isVisible)
        XCTAssertEqual(first.window.contentView?.bounds.width, 1_280)
        XCTAssertEqual(first.window.contentView?.bounds.height, 900)
        XCTAssertEqual(QuillCodeDesktopCoworkEvalWindow.visibleWindowCount, 1)
    }

    func testCoworkEvalReportDistinguishesRecoveredToolFailures() {
        let tools = [
            QuillCodeDesktopCoworkEvalReport.Tool(
                name: "host.shell.run",
                status: "failed",
                inputJSON: nil,
                outputJSON: nil
            ),
            QuillCodeDesktopCoworkEvalReport.Tool(
                name: "host.file.write",
                status: "done",
                inputJSON: nil,
                outputJSON: nil
            ),
            QuillCodeDesktopCoworkEvalReport.Tool(
                name: "host.file.read",
                status: "failed",
                inputJSON: nil,
                outputJSON: nil
            ),
        ]

        XCTAssertEqual(QuillCodeDesktopCoworkEvalReport.unrecoveredFailureCount(in: tools), 1)
    }

    func testCoworkEvalReportNamesIncompleteTerminalReasons() {
        XCTAssertEqual(
            QuillCodeDesktopCoworkEvalReport.stopReasonFields(.finished).name,
            "finished"
        )
        let ceiling = QuillCodeDesktopCoworkEvalReport.stopReasonFields(
            .toolStepCeilingExhausted(limit: 64)
        )
        XCTAssertEqual(ceiling.name, "tool-step-ceiling-exhausted")
        XCTAssertTrue(ceiling.detail?.contains("64-step") == true)
    }

    func testCoworkEvalScheduledAutomationCapturesPersistedContract() throws {
        let nextRun = Date(timeIntervalSince1970: 1_800_000_000)
        let automation = QuillAutomation(
            title: "Scheduled task: check competitor pricing",
            detail: "Check competitor pricing and notify me with a diff.",
            kind: .workspaceSchedule,
            scheduleKind: .cron,
            scheduleDescription: "Every Monday at 8:00 AM",
            nextRunAt: nextRun,
            recurrence: QuillAutomationRecurrence(
                interval: 1,
                unit: .weeks,
                weekdays: [2],
                hour: 8,
                minute: 0
            )
        )

        let report = QuillCodeDesktopCoworkEvalReport.ScheduledAutomation(automation)

        XCTAssertEqual(report.title, automation.title)
        XCTAssertEqual(report.kind, "workspace_schedule")
        XCTAssertEqual(report.status, "active")
        XCTAssertEqual(report.scheduleKind, "cron")
        XCTAssertEqual(report.scheduleDescription, "Every Monday at 8:00 AM")
        XCTAssertEqual(report.nextRunAt, nextRun)
        XCTAssertEqual(report.recurrence?.unit, "weeks")
        XCTAssertEqual(report.recurrence?.weekdays, [2])
        XCTAssertEqual(report.recurrence?.hour, 8)
    }

    func testDesktopSmokePixelValidationAcceptsConfiguredMinimumColorBuckets() throws {
        let stats = QuillCodeDesktopSmokePixelStats(
            report: QuillCodeDesktopSmokePixelReport(
                width: 1280,
                height: 900,
                opaquePixelRatio: 1,
                brightPixelRatio: 0.01,
                accentPixelRatio: 0,
                distinctColorBuckets: 14
            )
        )

        XCTAssertNoThrow(
            try stats.validate(
                expectedWidth: 1280,
                expectedHeight: 900,
                minDistinctColorBuckets: 14,
                minBrightPixelRatio: 0.0005,
                minAccentPixelRatio: 0
            )
        )

        let flatStats = QuillCodeDesktopSmokePixelStats(
            report: QuillCodeDesktopSmokePixelReport(
                width: 1280,
                height: 900,
                opaquePixelRatio: 1,
                brightPixelRatio: 0.01,
                accentPixelRatio: 0,
                distinctColorBuckets: 13
            )
        )
        XCTAssertThrowsError(
            try flatStats.validate(
                expectedWidth: 1280,
                expectedHeight: 900,
                minDistinctColorBuckets: 14,
                minBrightPixelRatio: 0.0005,
                minAccentPixelRatio: 0
            )
        )
    }

    func testDesktopWindowSmokeRequestParsesReportAndScreenshotPaths() {
        let request = QuillCodeDesktopWindowSmokeRequest(arguments: [
            "QuillCode",
            "--native-window-smoke",
            "--window-smoke-report",
            "/tmp/quillcode-window-report.json",
            "--window-smoke-screenshot",
            "/tmp/quillcode-window.png",
            "--window-smoke-state-root",
            "/tmp/quillcode-window-state"
        ])

        XCTAssertEqual(request?.reportPath, "/tmp/quillcode-window-report.json")
        XCTAssertEqual(request?.screenshotPath, "/tmp/quillcode-window.png")
        XCTAssertEqual(request?.stateRootPath, "/tmp/quillcode-window-state")
        XCTAssertNil(QuillCodeDesktopWindowSmokeRequest(arguments: ["QuillCode"]))
    }

    func testDesktopWindowSmokeWorkspaceUsesExplicitIsolatedStateRoot() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-window-smoke-root-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let request = try XCTUnwrap(QuillCodeDesktopWindowSmokeRequest(arguments: [
            "QuillCode",
            "--native-window-smoke",
            "--window-smoke-state-root",
            temporaryDirectory.path
        ]))
        let root = QuillCodeDesktopWindowSmokeWorkspaceRoot(request: request)
        let controller = root.makeController()

        XCTAssertEqual(root.root.path, temporaryDirectory.path)
        XCTAssertEqual(root.appState.path, temporaryDirectory.appendingPathComponent("app-state").path)
        XCTAssertEqual(root.workspace.path, temporaryDirectory.appendingPathComponent("workspace").path)
        XCTAssertEqual(controller.bootstrap.paths.home, root.appState)
        XCTAssertEqual(controller.workspaceRoot, root.workspace)
        XCTAssertNotEqual(controller.bootstrap.paths.home, QuillCodePaths().home)
        XCTAssertTrue(controller.model.root.projects.allSatisfy { $0.path == root.workspace.path })

        let reviewCommand = try XCTUnwrap(
            controller.surface.commands.first { $0.id == "toggle-review-panel" }
        )
        XCTAssertTrue(reviewCommand.isEnabled)
        XCTAssertFalse(controller.surface.review.isVisible)
        controller.runCommand(reviewCommand)
        XCTAssertTrue(controller.surface.review.isVisible)
        controller.runCommand(commandID: reviewCommand.id)
        XCTAssertFalse(controller.surface.review.isVisible)
    }

    func testDesktopRenderSmokeLaunchControllerUsesExplicitIsolatedWorkspace() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-render-smoke-root-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let request = try XCTUnwrap(QuillCodeDesktopSmokeRequest(arguments: [
            "QuillCode",
            "--native-render-smoke",
            "--smoke-workspace",
            temporaryDirectory.path
        ]))
        let root = try QuillCodeDesktopSmokeWorkspaceRoot(request: request)
        let controller = root.makeLaunchController()

        XCTAssertEqual(root.home.path, temporaryDirectory.appendingPathComponent("home").path)
        XCTAssertEqual(root.workspace.path, temporaryDirectory.appendingPathComponent("workspace").path)
        XCTAssertEqual(controller.bootstrap.paths.home, root.home)
        XCTAssertEqual(controller.workspaceRoot, root.workspace)
        XCTAssertNotEqual(controller.bootstrap.paths.home, QuillCodePaths().home)
        XCTAssertTrue(controller.model.root.projects.allSatisfy { $0.path == root.workspace.path })
    }

    func testDesktopWorkspaceRootResolverRejectsLaunchServicesRootAndHome() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-workspace-root-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let home = temporaryDirectory.appendingPathComponent("home", isDirectory: true)
        let project = temporaryDirectory.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)

        let rootFallback = QuillCodeDesktopWorkspaceRootResolver.resolve(
            currentDirectory: URL(fileURLWithPath: "/", isDirectory: true),
            userHome: home
        )
        let homeFallback = QuillCodeDesktopWorkspaceRootResolver.resolve(
            currentDirectory: home,
            userHome: home
        )
        let explicitProject = QuillCodeDesktopWorkspaceRootResolver.resolve(
            currentDirectory: project,
            userHome: home
        )
        let expectedFallback = home
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(QuillCodeDesktopWorkspaceRootResolver.fallbackDirectoryName, isDirectory: true)

        XCTAssertEqual(rootFallback, expectedFallback)
        XCTAssertEqual(homeFallback, expectedFallback)
        XCTAssertEqual(explicitProject, project.standardizedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedFallback.path))
    }

    func testDesktopBrowserSmokeReportDocumentsAgentInspection() {
        let report = QuillCodeDesktopBrowserSmokeReport(
            previewPath: "/tmp/browser-smoke.html",
            url: "file:///tmp/browser-smoke.html",
            title: "Browser Smoke",
            status: "Preview ready",
            sourceLabel: "Local HTML",
            inspectionDepth: "Static HTML snapshot",
            outline: ["H1: Browser Smoke"],
            textSnippet: "Native browser smoke preview text.",
            commentCount: 1,
            toolName: "host.browser.inspect",
            finalAnswer: "Inspected `Browser Smoke`. Native browser smoke preview text."
        )

        let dictionary = report.dictionary
        XCTAssertEqual(dictionary["title"] as? String, "Browser Smoke")
        XCTAssertEqual(dictionary["inspectionDepth"] as? String, "Static HTML snapshot")
        XCTAssertEqual(dictionary["commentCount"] as? Int, 1)
        XCTAssertEqual(dictionary["toolName"] as? String, "host.browser.inspect")
        XCTAssertEqual(dictionary["outline"] as? [String], ["H1: Browser Smoke"])
    }

    func testDesktopWindowSmokeReportIncludesNativeHitTargets() throws {
        let model = QuillCodeWorkspaceModel()
        let surface = model.surface()
        let nativeHitTargets = try QuillCodeDesktopNativeHitTargetSmoke.validatedReport(for: surface)
        let surfaceReport = try QuillCodeDesktopWindowSmokeSurfaceReport(surface: surface)
        let accessibilityActivation = QuillCodeDesktopAccessibilityActivationReport(
            liveAccessibilityActivation: "ax-press-sampled",
            requiredContractIDs: ["command.settings"],
            activatedContractIDs: ["command.settings"],
            skippedContractIDs: [],
            checks: [
                QuillCodeDesktopAccessibilityActivationCheck(
                    contractID: "command.settings",
                    selectorKind: "command-id",
                    selector: "settings",
                    resolvedIdentifier: "quillcode-sidebar-command-settings",
                    role: "AXButton",
                    label: "Settings",
                    activation: "AXPress",
                    expectedOutcome: "settings sheet becomes presented",
                    beforeValue: "false",
                    afterValue: "true",
                    axError: "success",
                    interactionEvidence: "AXPress changed observable controller state",
                    validationIssue: nil
                )
            ],
            validationIssues: []
        )
        let accessibilityFrameSamples = QuillCodeDesktopAccessibilityFrameSampleReport(
            liveAccessibilitySampling: "frame-sampled",
            minimumHitTarget: 40,
            minimumTargetClearance: 8,
            requiredContractIDs: ["composer.send"],
            sampledContractIDs: ["composer.send"],
            unresolvedRequiredContractIDs: [],
            skippedContractIDs: [],
            samples: [
                QuillCodeDesktopAccessibilityFrameSample(
                    contractID: "composer.send",
                    selectorKind: "test-id",
                    selector: "quillcode-send-button",
                    collisionScope: "composer:composer",
                    kind: "icon",
                    action: "press",
                    resolvedIdentifier: "quillcode-send-button",
                    role: "AXButton",
                    label: "Send message",
                    frame: CGRect(x: 100, y: 100, width: 44, height: 44),
                    requiredMinWidth: 44,
                    requiredMinHeight: 44,
                    requiredPeerClearance: 8,
                    allowsNestedInteractiveChildren: false,
                    requiresUnblockedInterior: true,
                    requiresTactileFeedback: true,
                    allowsTextSelection: false,
                    samplePoints: [[
                        "name": "center",
                        "x": 122,
                        "y": 122,
                        "hitTestAvailable": true,
                        "hitTestError": "",
                        "hitTestIdentifier": "quillcode-send-button",
                        "hitTestRole": "AXButton",
                        "hitTestLabel": "Send message",
                        "hitTestAncestorIdentifiers": [],
                        "hitTestMatchesTarget": true
                    ]]
                )
            ],
            validationIssues: []
        )
        let report = QuillCodeDesktopWindowSmokeReport(
            ok: true,
            appName: "Quill Cowork",
            bundleIdentifier: "co.lorehex.QuillCowork",
            windowTitle: "Quill Cowork",
            workspaceWindowCount: 1,
            windowFrame: CGRect(x: 0, y: 0, width: 1280, height: 928),
            contentSize: CGSize(width: 1280, height: 900),
            screenshotPath: "/tmp/quillcode-window.png",
            stateRootPath: "/tmp/quillcode-window-state",
            appStatePath: "/tmp/quillcode-window-state/app-state",
            workspacePath: "/tmp/quillcode-window-state/workspace",
            performance: QuillCodeDesktopPerformanceSnapshot(
                launchReadyMilliseconds: 742.5,
                initialResources: QuillCodeDesktopProcessResourceSnapshot(
                    residentMemoryBytes: 96 * 1_024 * 1_024,
                    threadCount: 18
                ),
                postInteractionResources: QuillCodeDesktopProcessResourceSnapshot(
                    residentMemoryBytes: 104 * 1_024 * 1_024,
                    threadCount: 20
                ),
                repeatedInteractionResources: QuillCodeDesktopProcessResourceSnapshot(
                    residentMemoryBytes: 108 * 1_024 * 1_024,
                    threadCount: 19
                )
            ),
            image: QuillCodeDesktopSmokePixelReport(
                width: 2560,
                height: 1800,
                opaquePixelRatio: 1,
                brightPixelRatio: 0.01,
                accentPixelRatio: 0.01,
                distinctColorBuckets: 48
            ),
            nativeHitTargets: nativeHitTargets,
            accessibilityFrameSamples: accessibilityFrameSamples,
            accessibilityActivation: accessibilityActivation,
            surface: surfaceReport
        )

        let json = String(data: try report.prettyJSON(), encoding: .utf8) ?? ""
        let jsonObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: report.prettyJSON()) as? [String: Any]
        )
        XCTAssertTrue(json.contains(#""nativeHitTargets""#))
        XCTAssertEqual(jsonObject["workspaceWindowCount"] as? Int, 1)
        XCTAssertTrue(json.contains(#""clickProbes""#))
        XCTAssertTrue(json.contains(#""quillcode-send-button""#))
        XCTAssertTrue(json.contains(#""collisionScope" : "composer:composer""#))
        XCTAssertTrue(json.contains(#""accessibilityFrameSamples""#))
        XCTAssertTrue(json.contains(#""liveAccessibilitySampling" : "frame-sampled""#))
        XCTAssertTrue(json.contains(#""accessibilityActivation""#))
        XCTAssertTrue(json.contains(#""liveAccessibilityActivation" : "ax-press-sampled""#))
        XCTAssertTrue(json.contains(#""expectedOutcome" : "settings sheet becomes presented""#))
        XCTAssertTrue(json.contains(#""activation" : "AXPress""#))
        XCTAssertTrue(json.contains(#""interactionEvidence" : "AXPress changed observable controller state""#))
        XCTAssertTrue(json.contains(#""hitTestAvailable" : true"#))
        XCTAssertTrue(json.contains(#""hitTestMatchesTarget" : true"#))
        XCTAssertTrue(json.contains(#""requiresTactileFeedback" : true"#))
        XCTAssertTrue(json.contains(#""allowsTextSelection" : false"#))
        XCTAssertTrue(json.contains(#""surface""#))
        XCTAssertTrue(json.contains(#""composerCanSend" : false"#))
        XCTAssertTrue(json.contains(#""measurement" : "initial-live-window""#))
        XCTAssertTrue(json.contains(#""postInteractionMeasurement" : "settled-after-native-interaction-sweep""#))
        XCTAssertTrue(json.contains(
            #""repeatedInteractionMeasurement" : "settled-after-repeated-native-interaction-sweep""#
        ))
        XCTAssertTrue(json.contains(#""interactionSweepCount" : 2"#))
        XCTAssertEqual(jsonObject["stateRootPath"] as? String, "/tmp/quillcode-window-state")
        XCTAssertEqual(jsonObject["appStatePath"] as? String, "/tmp/quillcode-window-state/app-state")
        XCTAssertEqual(jsonObject["workspacePath"] as? String, "/tmp/quillcode-window-state/workspace")
        XCTAssertEqual(
            (jsonObject["performance"] as? [String: Any])?["residentMemoryBytes"] as? Int,
            96 * 1_024 * 1_024
        )
        XCTAssertEqual(
            (jsonObject["performance"] as? [String: Any])?["postInteractionResidentMemoryBytes"] as? Int,
            104 * 1_024 * 1_024
        )
        XCTAssertEqual(
            (jsonObject["performance"] as? [String: Any])?["residentMemoryGrowthBytes"] as? Int,
            8 * 1_024 * 1_024
        )
        XCTAssertEqual(
            (jsonObject["performance"] as? [String: Any])?["repeatedInteractionResidentMemoryBytes"] as? Int,
            108 * 1_024 * 1_024
        )
        XCTAssertEqual(
            (jsonObject["performance"] as? [String: Any])?["repeatedInteractionResidentMemoryGrowthBytes"] as? Int,
            4 * 1_024 * 1_024
        )
        XCTAssertEqual(
            (jsonObject["performance"] as? [String: Any])?["repeatedInteractionThreadGrowth"] as? Int,
            -1
        )
    }

    func testComputerUseCoordinatorRefreshesForegroundApplication() async throws {
        let application = ComputerUseApplication(
            name: "Terminal",
            bundleIdentifier: "com.apple.Terminal"
        )
        let backend = StubComputerUseBackend(foregroundApplication: application)
        let model = QuillCodeWorkspaceModel()
        let coordinator = QuillCodeDesktopComputerUseCoordinator(backend: backend)

        coordinator.install(on: model)

        try await waitUntil(timeoutSeconds: 1) {
            model.surface().settings.computerUseForegroundApplication == application
        }
    }

    func testWindowAccessibilityFrameSamplerRequiresPrimarySidebarActions() {
        XCTAssertEqual(
            QuillCodeDesktopAccessibilityFrameSampler.requiredPrimarySidebarContractIDs,
            [
                "command.add-project",
                "command.new-chat",
                "command.search",
                "command.toggle-automations",
                "command.toggle-extensions",
                "command.settings",
                "project.clear"
            ]
        )
        XCTAssertTrue(QuillCodeDesktopAccessibilityFrameSampler.requiredLiveContractIDs.isSuperset(
            of: QuillCodeDesktopAccessibilityFrameSampler.requiredPrimarySidebarContractIDs
        ))
    }

    func testWindowAccessibilityActivationSamplerRequiresModelPickerNewChatSearchAndSafePrimaryActions() {
        XCTAssertEqual(
            QuillCodeDesktopAccessibilityActivationSampler.requiredActivationContractIDs,
            [
                "composer.model-picker",
                "command.new-chat",
                "command.search",
                "command.settings",
                "command.toggle-automations",
                "command.toggle-extensions",
                "command.toggle-memories",
                "command.toggle-activity",
                "command.toggle-review-panel",
                "onboarding.developer-key"
            ]
        )
        XCTAssertEqual(
            QuillCodeDesktopAccessibilityActivationSampler.repeatableActivationContractIDs,
            QuillCodeDesktopAccessibilityActivationSampler.requiredActivationContractIDs
                .subtracting(["onboarding.developer-key"])
        )
    }

    func testWindowAccessibilityActivationSamplerPreservesDeclaredOrderWithinPhases() {
        XCTAssertEqual(
            QuillCodeDesktopAccessibilityActivationSampler.orderedActivationContractIDs(
                includesInitialSurface: true
            ),
            [
                "onboarding.developer-key",
                "composer.model-picker",
                "command.search",
                "command.settings",
                "command.toggle-automations",
                "command.toggle-extensions",
                "command.toggle-memories",
                "command.toggle-activity",
                "command.toggle-review-panel",
                "command.new-chat"
            ]
        )
        XCTAssertEqual(
            QuillCodeDesktopAccessibilityActivationSampler.orderedActivationContractIDs(
                includesInitialSurface: false
            ).first,
            "composer.model-picker"
        )
    }

    func testNewChatActivationTransitionRequiresOneAddedSelectedThread() {
        let baselineID = UUID()
        let createdID = UUID()
        let before = QuillCodeDesktopAccessibilityActivationState.workspaceThreads(.init(
            selectedThreadID: baselineID,
            threadIDs: [baselineID]
        ))
        let after = QuillCodeDesktopAccessibilityActivationState.workspaceThreads(.init(
            selectedThreadID: createdID,
            threadIDs: [baselineID, createdID]
        ))

        XCTAssertNil(QuillCodeDesktopAccessibilityInteractionVerifier.newChatTransitionIssue(
            before: before,
            after: after
        ))
    }

    func testNewChatActivationTransitionRejectsMultipleOrUnselectedThreads() {
        let baselineID = UUID()
        let firstCreatedID = UUID()
        let secondCreatedID = UUID()
        let before = QuillCodeDesktopAccessibilityActivationState.workspaceThreads(.init(
            selectedThreadID: baselineID,
            threadIDs: [baselineID]
        ))
        let multipleAfter = QuillCodeDesktopAccessibilityActivationState.workspaceThreads(.init(
            selectedThreadID: firstCreatedID,
            threadIDs: [baselineID, firstCreatedID, secondCreatedID]
        ))
        let unselectedAfter = QuillCodeDesktopAccessibilityActivationState.workspaceThreads(.init(
            selectedThreadID: baselineID,
            threadIDs: [baselineID, firstCreatedID]
        ))

        XCTAssertNotNil(QuillCodeDesktopAccessibilityInteractionVerifier.newChatTransitionIssue(
            before: before,
            after: multipleAfter
        ))
        XCTAssertNotNil(QuillCodeDesktopAccessibilityInteractionVerifier.newChatTransitionIssue(
            before: before,
            after: unselectedAfter
        ))
    }

    private func waitUntil(
        timeoutSeconds: TimeInterval,
        condition: @MainActor @escaping () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while !condition() {
            if Date() > deadline {
                XCTFail("Timed out waiting for desktop condition", file: file, line: line)
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}
