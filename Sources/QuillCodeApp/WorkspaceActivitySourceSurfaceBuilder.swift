import QuillCodeCore

enum WorkspaceActivitySourceSurfaceBuilder {
    static func items(instructions: [ProjectInstruction], memories: [MemoryNote]) -> [ActivityItemSurface] {
        let instructionItems = instructions.prefix(4).map { instruction in
            ActivityItemSurface(
                id: "instruction-\(instruction.path)",
                title: WorkspaceActivityText.sourceTitle(instruction.path),
                detail: "\(instruction.path) · Scope: \(instruction.scopeLabel)",
                kind: "instruction",
                statusLabel: "rules"
            )
        }
        let memoryItems = memories.prefix(4).map { memory in
            ActivityItemSurface(
                id: "memory-\(memory.id)",
                title: memory.title,
                detail: memory.relativePath,
                kind: "memory",
                statusLabel: memory.scope.title
            )
        }
        return Array(instructionItems + memoryItems)
    }
}
