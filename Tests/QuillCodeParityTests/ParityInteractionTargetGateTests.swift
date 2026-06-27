import XCTest

final class ParityInteractionTargetGateTests: QuillCodeParityTestCase {
    func testNativeInteractionControlsUseSharedTargetContracts() throws {
        let sourceFiles = try Self.swiftSourceFiles(in: "Sources/QuillCodeApp")
        let targetMarkers = [
            "quillCodeTextButtonTarget",
            "quillCodeIconButtonTarget",
            "quillCodeFullRowButtonTarget",
            "quillCodeCapsuleButtonTarget",
            "quillCodeFormActionTarget",
            "quillCodeHitTarget",
            "quillCodeInteractiveTarget"
        ]
        var violations: [String] = []

        for file in sourceFiles {
            let lines = try String(contentsOf: file, encoding: .utf8)
                .components(separatedBy: .newlines)
            let relativePath = file.path.replacingOccurrences(
                of: Self.packageRoot().path + "/",
                with: ""
            )

            for (index, line) in lines.enumerated() {
                let controlWindow = window(in: lines, around: index, radius: 10)
                if usesCompactPlatformButtonStyle(line),
                   !targetMarkers.contains(where: controlWindow.contains) {
                    violations.append("\(relativePath):\(index + 1) compact platform button style lacks shared hit target")
                }

                if line.contains(".buttonStyle(QuillCodePressableButtonStyle())"),
                   !targetMarkers.contains(where: window(in: lines, around: index, radius: 18).contains) {
                    violations.append("\(relativePath):\(index + 1) pressable button lacks explicit shared hit target")
                }

                if line.contains(".labelStyle(.iconOnly)"),
                   !window(in: lines, around: index, radius: 8).contains("quillCodeIconButtonTarget") {
                    violations.append("\(relativePath):\(index + 1) icon-only control lacks icon hit target")
                }

                if line.contains(".onTapGesture") || line.contains(".gesture(") {
                    violations.append("\(relativePath):\(index + 1) gesture-based click target should be a Button or Link")
                }
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            "Interactive controls must use shared click-target contracts:\n\(violations.joined(separator: "\n"))"
        )
    }

    func testHTMLInteractionAuditRequiresNamedClickableTargets() throws {
        let auditHelperText = try String(
            contentsOf: Self.packageRoot()
                .appendingPathComponent("E2E/playwright/tests/interaction-audit-helpers.ts"),
            encoding: .utf8
        )

        XCTAssertTrue(
            auditHelperText.contains("accessibleName(element)")
                && auditHelperText.contains("missing_accessible_name"),
            "The rendered click-target audit should fail visible interactive elements that have no user-facing name."
        )
        XCTAssertTrue(
            auditHelperText.contains("button")
                && auditHelperText.contains("[role=\"button\"]")
                && auditHelperText.contains("[role=\"tab\"]")
                && auditHelperText.contains("textarea"),
            "The rendered click-target audit should cover native controls, ARIA controls, tabs, and text entry."
        )
    }

    private func usesCompactPlatformButtonStyle(_ line: String) -> Bool {
        line.contains(".buttonStyle(.bordered")
            || line.contains(".buttonStyle(.borderedProminent")
            || line.contains(".buttonStyle(.borderless")
            || line.contains(".buttonStyle(.plain")
    }

    private func window(in lines: [String], around index: Int, radius: Int) -> String {
        let lowerBound = max(0, index - radius)
        let upperBound = min(lines.count, index + radius + 1)
        return lines[lowerBound..<upperBound].joined(separator: "\n")
    }
}
