import Foundation
import QuillCodeCore
import QuillCodeTools

struct ProjectInstructionDiagnosticApplyPlan: Sendable, Hashable {
    let diagnosticID: String
    let selectedReferenceIndex: Int
    let summary: String
    let toolCall: ToolCall
}

enum ProjectInstructionDiagnosticApplyPlanner {
    static func supportedActions(
        for diagnostic: ProjectInstructionDiagnostic,
        instructions: [ProjectInstruction]
    ) -> [ActivityItemActionSurface] {
        if canApplyDeterministicConflictPatch(for: diagnostic) {
            return diagnostic.sourceReferences.enumerated().map { index, reference in
                applyAction(
                    title: keepTitle(for: reference),
                    diagnosticID: diagnostic.id,
                    selectedReferenceIndex: index
                )
            }
        }
        return supportedDuplicateScopeActions(for: diagnostic, instructions: instructions)
            + supportedLineRemovalActions(for: diagnostic)
    }

    static func plan(
        for diagnostic: ProjectInstructionDiagnostic,
        selectedReferenceIndex: Int,
        instructions: [ProjectInstruction]
    ) -> ProjectInstructionDiagnosticApplyPlan? {
        if canApplyDeterministicConflictPatch(for: diagnostic) {
            return semanticConflictPlan(
                for: diagnostic,
                selectedReferenceIndex: selectedReferenceIndex,
                instructions: instructions
            )
        }
        return duplicateScopePlan(
            for: diagnostic,
            selectedReferenceIndex: selectedReferenceIndex,
            instructions: instructions
        ) ?? lineRemovalPlan(
            for: diagnostic,
            selectedReferenceIndex: selectedReferenceIndex,
            instructions: instructions
        )
    }

    private static func semanticConflictPlan(
        for diagnostic: ProjectInstructionDiagnostic,
        selectedReferenceIndex: Int,
        instructions: [ProjectInstruction]
    ) -> ProjectInstructionDiagnosticApplyPlan? {
        guard diagnostic.sourceReferences.indices.contains(selectedReferenceIndex) else { return nil }

        let keepReference = diagnostic.sourceReferences[selectedReferenceIndex]
        let instructionByPath = instructionsByPath(instructions)
        let patches = diagnostic.sourceReferences.enumerated().compactMap { index, reference -> String? in
            guard index != selectedReferenceIndex,
                  let instruction = instructionByPath[reference.path]
            else {
                return nil
            }
            return ProjectInstructionDiagnosticPatchBuilder.removalPatch(for: reference, in: instruction)
        }
        guard patches.count == diagnostic.sourceReferences.count - 1 else {
            return nil
        }

        return ProjectInstructionDiagnosticApplyPlan(
            diagnosticID: diagnostic.id,
            selectedReferenceIndex: selectedReferenceIndex,
            summary: "Keep \(keepReference.role) and remove the conflicting instruction line.",
            toolCall: ToolCall(
                name: ToolDefinition.applyPatch.name,
                argumentsJSON: ToolArguments.json(["patch": patches.joined(separator: "\n")])
            )
        )
    }

    private static func duplicateScopePlan(
        for diagnostic: ProjectInstructionDiagnostic,
        selectedReferenceIndex: Int,
        instructions: [ProjectInstruction]
    ) -> ProjectInstructionDiagnosticApplyPlan? {
        guard duplicateScopeClearableIndexes(
            for: diagnostic,
            instructions: instructions
        ).contains(selectedReferenceIndex) else {
            return nil
        }
        let reference = diagnostic.sourceReferences[selectedReferenceIndex]
        let remainingReference = matchingDuplicateReference(
            excluding: selectedReferenceIndex,
            for: diagnostic,
            instructions: instructions
        )
        return ProjectInstructionDiagnosticApplyPlan(
            diagnosticID: diagnostic.id,
            selectedReferenceIndex: selectedReferenceIndex,
            summary: duplicateClearSummary(
                clearedPath: reference.path,
                remainingPath: remainingReference?.path
            ),
            toolCall: ToolCall(
                name: ToolDefinition.fileWrite.name,
                argumentsJSON: ToolArguments.json([
                    "content": "",
                    "path": reference.path
                ])
            )
        )
    }

    private static func canApplyDeterministicConflictPatch(for diagnostic: ProjectInstructionDiagnostic) -> Bool {
        diagnostic.isConflict
            && diagnostic.sourceReferences.count == 2
            && diagnostic.sourceReferences.allSatisfy {
                ProjectInstructionDiagnosticPatchBuilder.isSafeGeneratedToolPath($0.path)
            }
    }

    private static func supportedDuplicateScopeActions(
        for diagnostic: ProjectInstructionDiagnostic,
        instructions: [ProjectInstruction]
    ) -> [ActivityItemActionSurface] {
        duplicateScopeClearableIndexes(for: diagnostic, instructions: instructions).map { index in
            applyAction(
                title: "Clear duplicate \(diagnostic.sourceReferences[index].path)",
                diagnosticID: diagnostic.id,
                selectedReferenceIndex: index
            )
        }
    }

    private static func duplicateScopeClearableIndexes(
        for diagnostic: ProjectInstructionDiagnostic,
        instructions: [ProjectInstruction]
    ) -> [Int] {
        guard diagnostic.isDuplicateScope else { return [] }
        let instructionByPath = instructionsByPath(instructions)
        let normalizedByIndex = diagnostic.sourceReferences.enumerated().compactMap {
            index,
            reference -> (Int, String)? in
            guard ProjectInstructionDiagnosticPatchBuilder.isSafeGeneratedToolPath(reference.path),
                  let instruction = instructionByPath[reference.path]
            else {
                return nil
            }
            let normalized = ProjectInstructionDiagnosticPatchBuilder.normalizedContent(instruction.content)
            return normalized.isEmpty ? nil : (index, normalized)
        }
        let duplicateContents = Dictionary(grouping: normalizedByIndex, by: \.1)
            .filter { $0.value.count > 1 }
            .keys
        return normalizedByIndex
            .filter { duplicateContents.contains($0.1) }
            .map(\.0)
    }

    private static func matchingDuplicateReference(
        excluding selectedReferenceIndex: Int,
        for diagnostic: ProjectInstructionDiagnostic,
        instructions: [ProjectInstruction]
    ) -> ProjectInstructionDiagnosticSourceReference? {
        let instructionByPath = instructionsByPath(instructions)
        guard diagnostic.sourceReferences.indices.contains(selectedReferenceIndex),
              let selectedInstruction = instructionByPath[diagnostic.sourceReferences[selectedReferenceIndex].path]
        else {
            return nil
        }
        let selectedContent = ProjectInstructionDiagnosticPatchBuilder.normalizedContent(selectedInstruction.content)
        return diagnostic.sourceReferences.enumerated().first { index, reference in
            guard index != selectedReferenceIndex,
                  let instruction = instructionByPath[reference.path]
            else {
                return false
            }
            return ProjectInstructionDiagnosticPatchBuilder.normalizedContent(instruction.content) == selectedContent
        }?.element
    }

    private static func duplicateClearSummary(clearedPath: String, remainingPath: String?) -> String {
        "Clear duplicate \(clearedPath); identical guidance remains in \(remainingPath ?? "another source")."
    }

    private static func supportedLineRemovalActions(
        for diagnostic: ProjectInstructionDiagnostic
    ) -> [ActivityItemActionSurface] {
        guard let kind = ProjectInstructionDiagnosticLineRemovalKind.matching(diagnostic) else { return [] }
        return lineRemovalIndexes(for: diagnostic, kind: kind).map { index in
            applyAction(
                title: kind.actionTitle(path: diagnostic.sourceReferences[index].path),
                diagnosticID: diagnostic.id,
                selectedReferenceIndex: index
            )
        }
    }

    private static func lineRemovalPlan(
        for diagnostic: ProjectInstructionDiagnostic,
        selectedReferenceIndex: Int,
        instructions: [ProjectInstruction]
    ) -> ProjectInstructionDiagnosticApplyPlan? {
        guard let kind = ProjectInstructionDiagnosticLineRemovalKind.matching(diagnostic),
              lineRemovalIndexes(for: diagnostic, kind: kind).contains(selectedReferenceIndex)
        else {
            return nil
        }
        let selectedReference = diagnostic.sourceReferences[selectedReferenceIndex]
        let instructionByPath = instructionsByPath(instructions)
        guard let selectedInstruction = instructionByPath[selectedReference.path] else {
            return nil
        }
        let references = diagnostic.sourceReferences.filter {
            $0.path == selectedReference.path && $0.role == kind.referenceRole
        }
        guard let patch = ProjectInstructionDiagnosticPatchBuilder.removalPatch(
            for: references,
            in: selectedInstruction
        ) else {
            return nil
        }

        return ProjectInstructionDiagnosticApplyPlan(
            diagnosticID: diagnostic.id,
            selectedReferenceIndex: selectedReferenceIndex,
            summary: kind.summary(path: selectedReference.path),
            toolCall: ToolCall(
                name: ToolDefinition.applyPatch.name,
                argumentsJSON: ToolArguments.json(["patch": patch])
            )
        )
    }

    private static func lineRemovalIndexes(
        for diagnostic: ProjectInstructionDiagnostic,
        kind: ProjectInstructionDiagnosticLineRemovalKind
    ) -> [Int] {
        var seenPaths = Set<String>()
        return diagnostic.sourceReferences.enumerated().compactMap { index, reference in
            guard reference.role == kind.referenceRole,
                  ProjectInstructionDiagnosticPatchBuilder.isSafeGeneratedToolPath(reference.path),
                  seenPaths.insert(reference.path).inserted
            else {
                return nil
            }
            return index
        }
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

    private static func applyAction(
        title: String,
        diagnosticID: String,
        selectedReferenceIndex: Int
    ) -> ActivityItemActionSurface {
        ActivityItemActionSurface(
            title: title,
            commandID: WorkspaceInstructionDiagnosticCommand.applyCommandID(
                diagnosticID: diagnosticID,
                selectedReferenceIndex: selectedReferenceIndex
            ),
            kind: "apply"
        )
    }
}
