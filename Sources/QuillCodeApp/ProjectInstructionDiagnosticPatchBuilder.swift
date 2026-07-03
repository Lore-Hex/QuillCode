import Foundation
import QuillCodeCore

enum ProjectInstructionDiagnosticPatchBuilder {
    static func removalPatch(
        for reference: ProjectInstructionDiagnosticSourceReference,
        in instruction: ProjectInstruction
    ) -> String? {
        let lines = contentLines(instruction.content)
        let lineIndex = reference.lineNumber - 1
        guard lines.indices.contains(lineIndex),
              normalizedLine(lines[lineIndex]) == normalizedLine(reference.excerpt)
        else {
            return nil
        }

        let startLine = max(1, reference.lineNumber - 3)
        let endLine = min(lines.count, reference.lineNumber + 3)
        let oldCount = endLine - startLine + 1
        let newCount = oldCount - 1
        var patchLines = headerLines(
            path: instruction.path,
            startLine: startLine,
            oldCount: oldCount,
            newCount: newCount
        )
        for displayLineNumber in startLine...endLine {
            let line = lines[displayLineNumber - 1]
            patchLines.append(displayLineNumber == reference.lineNumber ? "-\(line)" : " \(line)")
        }
        return patchLines.joined(separator: "\n") + "\n"
    }

    static func removalPatch(
        for references: [ProjectInstructionDiagnosticSourceReference],
        in instruction: ProjectInstruction
    ) -> String? {
        let lines = contentLines(instruction.content)
        let lineIndexesToRemove = Set(references.compactMap { reference -> Int? in
            let lineIndex = reference.lineNumber - 1
            guard lines.indices.contains(lineIndex),
                  normalizedLine(lines[lineIndex]) == normalizedLine(reference.excerpt)
            else {
                return nil
            }
            return lineIndex
        })
        guard !lineIndexesToRemove.isEmpty,
              lineIndexesToRemove.count == references.count
        else {
            return nil
        }

        let oldCount = max(lines.count, 1)
        let newCount = lines.count - lineIndexesToRemove.count
        var patchLines = headerLines(
            path: instruction.path,
            startLine: 1,
            oldCount: oldCount,
            newCount: newCount
        )
        for (index, line) in lines.enumerated() {
            patchLines.append(lineIndexesToRemove.contains(index) ? "-\(line)" : " \(line)")
        }
        return patchLines.joined(separator: "\n") + "\n"
    }

    static func normalizedContent(_ content: String) -> String {
        content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isSafeGeneratedToolPath(_ path: String) -> Bool {
        !path.isEmpty
            && !path.hasPrefix("/")
            && path != ".."
            && !path.hasPrefix("../")
            && !path.contains("/../")
            && !path.contains(where: \.isWhitespace)
    }

    private static func headerLines(
        path: String,
        startLine: Int,
        oldCount: Int,
        newCount: Int
    ) -> [String] {
        [
            "diff --git a/\(path) b/\(path)",
            "--- a/\(path)",
            "+++ b/\(path)",
            "@@ -\(startLine),\(oldCount) +\(startLine),\(newCount) @@"
        ]
    }

    private static func contentLines(_ content: String) -> [String] {
        var lines = content.components(separatedBy: "\n")
        if content.hasSuffix("\n"), lines.last == "" {
            lines.removeLast()
        }
        return lines
    }

    private static func normalizedLine(_ line: String) -> String {
        line.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
