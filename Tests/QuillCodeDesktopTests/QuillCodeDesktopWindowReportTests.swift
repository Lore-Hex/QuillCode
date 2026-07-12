import Foundation
import XCTest
import QuillCodeApp
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
            "/tmp/quillcode-window.png"
        ])

        XCTAssertEqual(request?.reportPath, "/tmp/quillcode-window-report.json")
        XCTAssertEqual(request?.screenshotPath, "/tmp/quillcode-window.png")
        XCTAssertNil(QuillCodeDesktopWindowSmokeRequest(arguments: ["QuillCode"]))
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
        XCTAssertTrue(json.contains(#""hitTestAvailable" : true"#))
        XCTAssertTrue(json.contains(#""hitTestMatchesTarget" : true"#))
        XCTAssertTrue(json.contains(#""requiresTactileFeedback" : true"#))
        XCTAssertTrue(json.contains(#""allowsTextSelection" : false"#))
        XCTAssertTrue(json.contains(#""surface""#))
        XCTAssertTrue(json.contains(#""composerCanSend" : false"#))
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
