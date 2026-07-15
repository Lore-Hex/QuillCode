import Foundation
import XCTest
import QuillCodeApp
import QuillCodePersistence
import QuillComputerUseKit
@testable import quill_code_desktop

@MainActor
final class QuillCodeDesktopWindowReportTests: XCTestCase {
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
            appName: "QuillCode",
            bundleIdentifier: "co.lorehex.QuillCode",
            windowTitle: "QuillCode",
            windowFrame: CGRect(x: 0, y: 0, width: 1280, height: 928),
            contentSize: CGSize(width: 1280, height: 900),
            screenshotPath: "/tmp/quillcode-window.png",
            stateRootPath: "/tmp/quillcode-window-state",
            appStatePath: "/tmp/quillcode-window-state/app-state",
            workspacePath: "/tmp/quillcode-window-state/workspace",
            image: QuillCodeDesktopSmokePixelReport(
                width: 2560,
                height: 1800,
                opaquePixelRatio: 1,
                brightPixelRatio: 0.01,
                blueAccentPixelRatio: 0.01,
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
        XCTAssertEqual(jsonObject["stateRootPath"] as? String, "/tmp/quillcode-window-state")
        XCTAssertEqual(jsonObject["appStatePath"] as? String, "/tmp/quillcode-window-state/app-state")
        XCTAssertEqual(jsonObject["workspacePath"] as? String, "/tmp/quillcode-window-state/workspace")
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
                "command.toggle-review-panel"
            ]
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
