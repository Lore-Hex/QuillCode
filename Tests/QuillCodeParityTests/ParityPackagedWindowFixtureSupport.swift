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
            "minimumHitTarget": 40,
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
        let values = accessibilityActivationValues(contractID: contractID)
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
                "beforeValue": "\(values.before)",
                "afterValue": "\(values.after)",
                "axError": "success",
                "interactionEvidence": "\(accessibilityActivationEvidence(contractID: contractID))",
                "ok": true,
                "validationIssue": ""
              }
        """
    }

    static func accessibilityActivationExpectedOutcome(contractID: String) -> String {
        switch contractID {
        case "composer.model-picker":
            return "model picker opens, focuses search, and surfaces a catalog result"
        case "command.new-chat":
            return "creates and selects exactly one chat, then focuses its composer"
        case "command.search":
            return "search dialog opens, focuses its field, and accepts text"
        case "command.settings":
            return "settings dialog renders its primary controls and dismisses through Close"
        case "command.toggle-automations":
            return "Automations renders its Create control and dismisses through Close"
        case "command.toggle-extensions":
            return "Extensions renders its Add control and dismisses through Close"
        case "command.toggle-memories":
            return "Memories renders its Add control and dismisses through Close"
        case "command.toggle-activity":
            return "Activity renders its task summary, dismisses through Close, and restores workspace width"
        case "command.toggle-review-panel":
            return "Review renders its scope control and dismisses through Close"
        default:
            return "observable controller state changes"
        }
    }

    static func accessibilityActivationEvidence(contractID: String) -> String {
        switch contractID {
        case "composer.model-picker":
            return "quillcode-model-picker-search focused, accepted reversible AXValue text entry, and surfaced the Prometheus 1.0 model option"
        case "command.new-chat":
            return "created exactly one selected chat and quillcode-composer-input focused with reversible AXValue text entry"
        case "command.search":
            return "quillcode-search-input focused and accepted reversible AXValue text entry"
        case "command.settings":
            return "rendered Settings with its notifications control and dismissed through quillcode-settings-close with AXPress"
        case "command.toggle-automations":
            return "rendered Automations with its Create control and dismissed through quillcode-automations-close with AXPress"
        case "command.toggle-extensions":
            return "rendered Extensions with its Add control and dismissed through quillcode-extensions-close with AXPress"
        case "command.toggle-memories":
            return "rendered Memories with its Add control and dismissed through quillcode-memories-close with AXPress"
        case "command.toggle-activity":
            return "rendered Activity with its task summary, dismissed through quillcode-activity-close with AXPress, and restored composer width from 480 to 800 points"
        case "command.toggle-review-panel":
            return "rendered Review with its scope control and dismissed through quillcode-review-close with AXPress"
        default:
            return "AXPress changed observable controller state"
        }
    }

    static func accessibilityActivationValues(contractID: String) -> (before: String, after: String) {
        if contractID == "command.new-chat" {
            return ("selected=baseline;count=1", "selected=created;count=2")
        }
        return ("false", "true")
    }
}
