import Foundation
import QuillCodeCore

public struct MemoryConflictSideSurface: Codable, Sendable, Hashable {
    public var id: String
    public var scopeLabel: String
    public var title: String
    public var preview: String
    public var relativePath: String
    public var editCommandID: String?

    init(note: MemoryNote, canEditProjectMemory: Bool) {
        let surface = MemoryNoteSurface(note: note, canEditProjectMemory: canEditProjectMemory)
        self.id = surface.id
        self.scopeLabel = surface.scopeLabel
        self.title = surface.title
        self.preview = surface.preview
        self.relativePath = surface.relativePath
        self.editCommandID = surface.editCommandID
    }
}

public struct MemoryConflictSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var summary: String
    public var global: MemoryConflictSideSurface
    public var project: MemoryConflictSideSurface

    init(
        subject: String,
        global: MemoryNote,
        project: MemoryNote,
        canEditProjectMemory: Bool
    ) {
        self.id = "memory-conflict:\(global.id):\(project.id):\(Self.slug(subject))"
        self.title = "Memory conflict: \(subject)"
        self.summary = [
            "Global and project memories disagree about \(subject).",
            "Review which note should guide this project."
        ].joined(separator: " ")
        self.global = MemoryConflictSideSurface(note: global, canEditProjectMemory: canEditProjectMemory)
        self.project = MemoryConflictSideSurface(note: project, canEditProjectMemory: canEditProjectMemory)
    }

    private static func slug(_ value: String) -> String {
        let scalars = value.lowercased().unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        }
        return String(scalars)
            .split(separator: "-")
            .joined(separator: "-")
    }
}
