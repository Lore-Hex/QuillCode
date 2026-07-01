import QuillCodeCore

enum WorkspaceActivitySourceSurfaceBuilder {
    static func items(
        instructions: [ProjectInstruction],
        memories: [MemoryNote],
        dismissedInstructionDiagnosticIDs: Set<String> = []
    ) -> [ActivityItemSurface] {
        let instructionItems = instructions.prefix(4).map { instruction in
            ActivityItemSurface(
                id: "instruction-\(instruction.path)",
                title: WorkspaceActivityText.sourceTitle(instruction.path),
                detail: "\(instruction.path) · Scope: \(instruction.scopeLabel)",
                kind: "instruction",
                statusLabel: instruction.wasTruncated ? "truncated" : "rules",
                actions: [
                    ActivityItemActionSurface(
                        title: "Open",
                        commandID: WorkspaceActivitySourceCommand.openCommandID(path: instruction.path),
                        kind: "open"
                    ),
                    ActivityItemActionSurface(
                        title: "Edit",
                        commandID: WorkspaceActivitySourceCommand.editCommandID(path: instruction.path),
                        kind: "edit"
                    )
                ]
            )
        }
        let allDiagnosticItems = ProjectInstructionDiagnosticsBuilder
            .diagnostics(for: instructions)
            .filter { !dismissedInstructionDiagnosticIDs.contains($0.id) }
            .map { diagnostic in
                let sourceReference = diagnostic.sourceReferences.first
                return ActivityItemSurface(
                    id: diagnostic.id,
                    title: diagnostic.title,
                    detail: diagnostic.detail,
                    kind: "instruction-diagnostic",
                    statusLabel: diagnostic.statusLabel,
                    actions: diagnosticActions(
                        diagnostic: diagnostic,
                        sourceReference: sourceReference
                    )
                    + ProjectInstructionDiagnosticPatchPlanner.supportedKeepActions(for: diagnostic)
                    + [
                        ActivityItemActionSurface(
                            title: "Resolve",
                            commandID: WorkspaceInstructionDiagnosticCommand.resolveCommandID(
                                diagnosticID: diagnostic.id
                            ),
                            kind: "resolve"
                        ),
                        ActivityItemActionSurface(
                            title: "Dismiss",
                            commandID: WorkspaceInstructionDiagnosticCommand.dismissCommandID(
                                diagnosticID: diagnostic.id
                            ),
                            kind: "dismiss"
                        )
                    ]
                )
            }
        let diagnosticItems = Array(
            (allDiagnosticItems.filter { $0.statusLabel == ProjectInstructionDiagnosticStatusLabel.conflict }
                + allDiagnosticItems.filter {
                    $0.statusLabel != ProjectInstructionDiagnosticStatusLabel.conflict
                })
                .prefix(4)
        )
        let memoryItems = memories.prefix(4).map { memory in
            ActivityItemSurface(
                id: "memory-\(memory.id)",
                title: memory.title,
                detail: memory.relativePath,
                kind: "memory",
                statusLabel: memory.scope.title
            )
        }
        return Array(instructionItems + diagnosticItems + memoryItems)
    }

    private static func diagnosticActions(
        diagnostic: ProjectInstructionDiagnostic,
        sourceReference: ProjectInstructionDiagnosticSourceReference?
    ) -> [ActivityItemActionSurface] {
        guard let sourceReference else { return [] }
        return [
            ActivityItemActionSurface(
                title: "Open Source",
                commandID: WorkspaceActivitySourceCommand.openCommandID(
                    path: sourceReference.path,
                    lineNumber: sourceReference.lineNumber
                ),
                kind: "open"
            ),
            ActivityItemActionSurface(
                title: "Edit Source",
                commandID: WorkspaceActivitySourceCommand.editCommandID(
                    path: sourceReference.path,
                    lineNumber: sourceReference.lineNumber
                ),
                kind: "edit"
            )
        ]
    }
}
