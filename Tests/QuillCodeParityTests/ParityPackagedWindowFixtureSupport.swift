extension QuillCodeParityTestCase {
    static var minimalPackagedWindowReport: String {
        minimalPackagedWindowReport()
    }

    static func minimalPackagedWindowReport(accessibilityFrameSamples: String? = nil) -> String {
        let commandIDs = minimalPackagedWindowCommandIDs
            .map { #"              "\#($0)""# }
            .joined(separator: ",\n")
        let surfaceContracts = ([minimalComposerSurfaceContractJSON] + minimalPackagedWindowCommandIDs.map(commandSurfaceContractJSON))
            .joined(separator: ",\n")
        let clickProbes = ([minimalComposerClickProbeJSON] + minimalPackagedWindowCommandIDs.map(commandClickProbeJSON))
            .joined(separator: ",\n")
        let accessibilityFrameSamplesFragment = accessibilityFrameSamples.map { ",\n\($0)" } ?? ""

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
        \(accessibilityFrameSamplesFragment)
        }
        """
    }

    static func minimalPackagedWindowAccessibilityFrameReport(
        firstSampleHitTestMatchesTarget: Bool = true
    ) -> String {
        minimalPackagedWindowReport(
            accessibilityFrameSamples: accessibilityEvidenceJSON(
                firstSampleHitTestMatchesTarget: firstSampleHitTestMatchesTarget
            )
        )
    }

    static func accessibilityEvidenceJSON(firstSampleHitTestMatchesTarget: Bool) -> String {
        """
        \(accessibilityFrameSamplesJSON(firstSampleHitTestMatchesTarget: firstSampleHitTestMatchesTarget)),
        \(accessibilityActivationJSON())
        """
    }

    static func accessibilityFrameSamplesJSON(firstSampleHitTestMatchesTarget: Bool) -> String {
        let contractIDs = requiredLiveAccessibilityContractIDs
            .map { #"              "\#($0)""# }
            .joined(separator: ",\n")
        let samples = requiredLiveAccessibilityContractIDs.enumerated()
            .map { index, contractID in
                accessibilityFrameSampleJSON(
                    contractID: contractID,
                    index: index,
                    hitTestMatchesTarget: index == 0 ? firstSampleHitTestMatchesTarget : true
                )
            }
            .joined(separator: ",\n")

        return """
          "accessibilityFrameSamples": {
            "ok": true,
            "liveAccessibilitySampling": "frame-sampled",
            "minimumHitTarget": 44,
            "minimumTargetClearance": 8,
            "requiredContractIDs": [
        \(contractIDs)
            ],
            "sampledContractIDs": [
        \(contractIDs)
            ],
            "unresolvedRequiredContractIDs": [],
            "skippedContractIDs": [],
            "sampleCount": \(requiredLiveAccessibilityContractIDs.count),
            "samples": [
        \(samples)
            ],
            "validationIssues": []
          }
        """
    }

    static func accessibilityFrameSampleJSON(
        contractID: String,
        index: Int,
        hitTestMatchesTarget: Bool
    ) -> String {
        let x = Double(100 + (index * 64))
        let y = 120.0
        let width = 44.0
        let height = 44.0
        let identifier = "quillcode-\(contractID.replacingOccurrences(of: ".", with: "-"))"
        let hitTestIdentifier = hitTestMatchesTarget ? identifier : "quillcode-blocker"
        let samplePoints = accessibilitySamplePointsJSON(
            frameX: x,
            frameY: y,
            frameWidth: width,
            frameHeight: height,
            hitTestIdentifier: hitTestIdentifier,
            hitTestMatchesTarget: hitTestMatchesTarget
        )

        return """
              {
                "contractID": "\(contractID)",
                "selectorKind": "test-id",
                "selector": "\(identifier)",
                "collisionScope": "accessibility-fixture:\(contractID)",
                "kind": "fullRow",
                "action": "press",
                "resolvedIdentifier": "\(identifier)",
                "role": "AXButton",
                "label": "\(contractID)",
                "frame": {
                  "x": \(x),
                  "y": \(y),
                  "width": \(width),
                  "height": \(height)
                },
                "requiredMinWidth": 44,
                "requiredMinHeight": 44,
                "requiredPeerClearance": 8,
                "allowsNestedInteractiveChildren": false,
                "requiresUnblockedInterior": true,
                "requiresTactileFeedback": true,
                "allowsTextSelection": false,
                "samplePoints": [
        \(samplePoints)
                ]
              }
        """
    }

    static func accessibilitySamplePointsJSON(
        frameX: Double,
        frameY: Double,
        frameWidth: Double,
        frameHeight: Double,
        hitTestIdentifier: String,
        hitTestMatchesTarget: Bool
    ) -> String {
        expectedSamplePoints.map { samplePoint in
            let x = frameX + (frameWidth * samplePoint.x)
            let y = frameY + (frameHeight * samplePoint.y)
            return """
                  {
                    "name": "\(samplePoint.name)",
                    "x": \(x),
                    "y": \(y),
                    "hitTestAvailable": true,
                    "hitTestError": "",
                    "hitTestIdentifier": "\(hitTestIdentifier)",
                    "hitTestRole": "AXButton",
                    "hitTestLabel": "\(hitTestIdentifier)",
                    "hitTestAncestorIdentifiers": [],
                    "hitTestMatchesTarget": \(hitTestMatchesTarget)
                  }
            """
        }
        .joined(separator: ",\n")
    }

    static let requiredLiveAccessibilityContractIDs = [
        "command.new-chat",
        "command.search",
        "command.settings",
        "command.toggle-automations",
        "command.toggle-extensions",
        "composer.input",
        "composer.mode-picker",
        "composer.model-picker",
        "composer.send",
        "sidebar.tools-menu",
        "top-bar.overflow"
    ]

    static let requiredLiveAccessibilityActivationContractIDs = [
        "command.settings",
        "command.toggle-automations",
        "command.toggle-extensions"
    ]

    static func accessibilityActivationJSON() -> String {
        let contractIDs = requiredLiveAccessibilityActivationContractIDs
            .map { #"              "\#($0)""# }
            .joined(separator: ",\n")
        let checks = requiredLiveAccessibilityActivationContractIDs
            .map(accessibilityActivationCheckJSON)
            .joined(separator: ",\n")

        return """
          "accessibilityActivation": {
            "ok": true,
            "liveAccessibilityActivation": "ax-press-sampled",
            "requiredContractIDs": [
        \(contractIDs)
            ],
            "activatedContractIDs": [
        \(contractIDs)
            ],
            "skippedContractIDs": [],
            "checkCount": \(requiredLiveAccessibilityActivationContractIDs.count),
            "checks": [
        \(checks)
            ],
            "validationIssues": []
          }
        """
    }

    static func accessibilityActivationCheckJSON(contractID: String) -> String {
        let commandID = String(contractID.dropFirst("command.".count))
        return """
              {
                "contractID": "\(contractID)",
                "selectorKind": "command-id",
                "selector": "\(commandID)",
                "resolvedIdentifier": "quillcode-sidebar-command-\(commandID)",
                "role": "AXButton",
                "label": "\(commandID)",
                "activation": "AXPress",
                "expectedOutcome": "\(accessibilityActivationExpectedOutcome(contractID: contractID))",
                "beforeValue": "false",
                "afterValue": "true",
                "axError": "success",
                "ok": true,
                "validationIssue": ""
              }
        """
    }

    static func accessibilityActivationExpectedOutcome(contractID: String) -> String {
        switch contractID {
        case "command.settings":
            return "settings sheet becomes presented"
        case "command.toggle-automations":
            return "automations pane visibility toggles"
        case "command.toggle-extensions":
            return "extensions pane visibility toggles"
        default:
            return "observable controller state changes"
        }
    }
}
