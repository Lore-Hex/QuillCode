extension QuillCodeParityTestCase {
    static var minimalClickProbeReport: String {
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
                "requiresUnblockedInterior": true,
                "requiresTactileFeedback": true,
                "allowsTextSelection": false
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
                "requiresTactileFeedback": true,
                "allowsTextSelection": false,
                "requiredMinWidth": 44,
                "requiredMinHeight": 44,
                "requiredPeerClearance": 8,
                "samplePoints": [
                  {"name": "center", "x": 0.5, "y": 0.5},
                  {"name": "leading-edge", "x": 0.08, "y": 0.5},
                  {"name": "leading-interior", "x": 0.18, "y": 0.5},
                  {"name": "trailing-edge", "x": 0.92, "y": 0.5},
                  {"name": "trailing-interior", "x": 0.82, "y": 0.5},
                  {"name": "top-edge", "x": 0.5, "y": 0.08},
                  {"name": "top-interior", "x": 0.5, "y": 0.18},
                  {"name": "bottom-edge", "x": 0.5, "y": 0.92},
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

    static let expectedSamplePoints: [(name: String, x: Double, y: Double)] = [
        ("bottom-edge", 0.5, 0.92),
        ("bottom-interior", 0.5, 0.82),
        ("center", 0.5, 0.5),
        ("leading-edge", 0.08, 0.5),
        ("leading-interior", 0.18, 0.5),
        ("top-edge", 0.5, 0.08),
        ("top-interior", 0.5, 0.18),
        ("trailing-edge", 0.92, 0.5),
        ("trailing-interior", 0.82, 0.5)
    ]

    static let minimalPackagedWindowCommandIDs = [
        "new-chat",
        "command-palette",
        "keyboard-shortcuts",
        "settings",
        "toggle-terminal",
        "toggle-browser",
        "stop-all",
        "disconnect-all"
    ]

    static var minimalComposerSurfaceContractJSON: String {
        """
              {
                "id": "composer.send",
                "testID": "quillcode-send-button",
                "collisionScope": "composer:composer",
                "kind": "icon",
                "action": "press",
                "allowsNestedInteractiveChildren": false,
                "requiresUnblockedInterior": true,
                "requiresTactileFeedback": true,
                "allowsTextSelection": false
              }
        """
    }

    static var minimalComposerClickProbeJSON: String {
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
                "requiresTactileFeedback": true,
                "allowsTextSelection": false,
                "requiredMinWidth": 44,
                "requiredMinHeight": 44,
                "requiredPeerClearance": 8,
                "samplePoints": [
                  {"name": "center", "x": 0.5, "y": 0.5},
                  {"name": "leading-edge", "x": 0.08, "y": 0.5},
                  {"name": "leading-interior", "x": 0.18, "y": 0.5},
                  {"name": "trailing-edge", "x": 0.92, "y": 0.5},
                  {"name": "trailing-interior", "x": 0.82, "y": 0.5},
                  {"name": "top-edge", "x": 0.5, "y": 0.08},
                  {"name": "top-interior", "x": 0.5, "y": 0.18},
                  {"name": "bottom-edge", "x": 0.5, "y": 0.92},
                  {"name": "bottom-interior", "x": 0.5, "y": 0.82}
                ]
              }
        """
    }

    static func commandSurfaceContractJSON(_ commandID: String) -> String {
        """
              {
                "id": "command.\(commandID)",
                "commandID": "\(commandID)",
                "collisionScope": "command:workspace-chrome",
                "kind": "fullRow",
                "action": "press",
                "allowsNestedInteractiveChildren": false,
                "requiresUnblockedInterior": true,
                "requiresTactileFeedback": true,
                "allowsTextSelection": false
              }
        """
    }

    static func commandClickProbeJSON(_ commandID: String) -> String {
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
                "requiresTactileFeedback": true,
                "allowsTextSelection": false,
                "requiredMinWidth": 44,
                "requiredMinHeight": 44,
                "requiredPeerClearance": 8,
                "samplePoints": [
                  {"name": "center", "x": 0.5, "y": 0.5},
                  {"name": "leading-edge", "x": 0.08, "y": 0.5},
                  {"name": "leading-interior", "x": 0.18, "y": 0.5},
                  {"name": "trailing-edge", "x": 0.92, "y": 0.5},
                  {"name": "trailing-interior", "x": 0.82, "y": 0.5},
                  {"name": "top-edge", "x": 0.5, "y": 0.08},
                  {"name": "top-interior", "x": 0.5, "y": 0.18},
                  {"name": "bottom-edge", "x": 0.5, "y": 0.92},
                  {"name": "bottom-interior", "x": 0.5, "y": 0.82}
                ]
              }
        """
    }
}
