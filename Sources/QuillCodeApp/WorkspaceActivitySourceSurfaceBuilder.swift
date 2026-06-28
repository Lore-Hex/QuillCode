import QuillCodeCore

enum WorkspaceActivitySourceSurfaceBuilder {
    static func items(instructions: [ProjectInstruction], memories: [MemoryNote]) -> [ActivityItemSurface] {
        let instructionItems = instructions.prefix(4).map { instruction in
            ActivityItemSurface(
                id: "instruction-\(instruction.path)",
                title: WorkspaceActivityText.sourceTitle(instruction.path),
                detail: "\(instruction.path) · Scope: \(instruction.scopeLabel)",
                kind: "instruction",
                statusLabel: instruction.wasTruncated ? "truncated" : "rules"
            )
        }
        let allDiagnosticItems = ProjectInstructionDiagnosticsBuilder
            .diagnostics(for: instructions)
            .map { diagnostic in
                ActivityItemSurface(
                    id: diagnostic.id,
                    title: diagnostic.title,
                    detail: diagnostic.detail,
                    kind: "instruction-diagnostic",
                    statusLabel: diagnostic.statusLabel
                )
            }
        let diagnosticItems = Array(
            (allDiagnosticItems.filter { $0.statusLabel == "conflict" }
                + allDiagnosticItems.filter { $0.statusLabel != "conflict" })
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
}
