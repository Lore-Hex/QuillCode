import Foundation
import QuillCodeCore

struct ProjectInstructionDiagnosticPatchPlan: Sendable, Hashable {
    let diagnosticID: String
    let keepReferenceIndex: Int
    let summary: String
    let patch: String
}

enum ProjectInstructionDiagnosticPatchPlanner {
    static func supportedKeepActions(for diagnostic: ProjectInstructionDiagnostic) -> [ActivityItemActionSurface] {
        guard canApplyDeterministicConflictPatch(for: diagnostic) else { return [] }
        return diagnostic.sourceReferences.enumerated().map { index, reference in
            ActivityItemActionSurface(
                title: keepTitle(for: reference),
                commandID: WorkspaceInstructionDiagnosticCommand.applyCommandID(
                    diagnosticID: diagnostic.id,
                    keepReferenceIndex: index
                ),
                kind: "apply"
            )
        }
    }

    static func plan(
        for diagnostic: ProjectInstructionDiagnostic,
        keepReferenceIndex: Int,
        instructions: [ProjectInstruction]
    ) -> ProjectInstructionDiagnosticPatchPlan? {
        guard canApplyDeterministicConflictPatch(for: diagnostic),
              diagnostic.sourceReferences.indices.contains(keepReferenceIndex)
        else {
            return nil
        }

        let keepReference = diagnostic.sourceReferences[keepReferenceIndex]
        let instructionByPath = instructionsByPath(instructions)
        let patches = diagnostic.sourceReferences.enumerated().compactMap { index, reference -> String? in
            guard index != keepReferenceIndex,
                  let instruction = instructionByPath[reference.path]
            else {
                return nil
            }
            return removalPatch(for: reference, in: instruction)
        }
        guard patches.count == diagnostic.sourceReferences.count - 1 else {
            return nil
        }

        return ProjectInstructionDiagnosticPatchPlan(
            diagnosticID: diagnostic.id,
            keepReferenceIndex: keepReferenceIndex,
            summary: "Keep \(keepReference.role) and remove the conflicting instruction line.",
            patch: patches.joined(separator: "\n")
        )
    }

    private static func canApplyDeterministicConflictPatch(for diagnostic: ProjectInstructionDiagnostic) -> Bool {
        diagnostic.isConflict
            && diagnostic.sourceReferences.count == 2
            && diagnostic.sourceReferences.allSatisfy { isSafeGeneratedPatchPath($0.path) }
    }

    private static func instructionsByPath(_ instructions: [ProjectInstruction]) -> [String: ProjectInstruction] {
        instructions.reduce(into: [:]) { partial, instruction in
            if partial[instruction.path] == nil {
                partial[instruction.path] = instruction
            }
        }
    }

    private static func keepTitle(for reference: ProjectInstructionDiagnosticSourceReference) -> String {
        "Keep \(reference.role)"
    }

    private static func removalPatch(
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
        var patchLines = [
            "diff --git a/\(instruction.path) b/\(instruction.path)",
            "--- a/\(instruction.path)",
            "+++ b/\(instruction.path)",
            "@@ -\(startLine),\(oldCount) +\(startLine),\(newCount) @@"
        ]
        for displayLineNumber in startLine...endLine {
            let line = lines[displayLineNumber - 1]
            patchLines.append(displayLineNumber == reference.lineNumber ? "-\(line)" : " \(line)")
        }
        return patchLines.joined(separator: "\n") + "\n"
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

    private static func isSafeGeneratedPatchPath(_ path: String) -> Bool {
        !path.isEmpty
            && !path.hasPrefix("/")
            && path != ".."
            && !path.hasPrefix("../")
            && !path.contains("/../")
            && !path.contains(where: \.isWhitespace)
    }
}
