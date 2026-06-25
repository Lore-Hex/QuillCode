import Foundation
import QuillCodeCore

public struct MemoryNoteSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var scope: MemoryScope
    public var scopeLabel: String
    public var title: String
    public var preview: String
    public var relativePath: String
    public var byteCountLabel: String
    public var canEdit: Bool
    public var editCommandID: String?
    public var canDelete: Bool
    public var deleteCommandID: String?

    public init(note: MemoryNote, canEditProjectMemory: Bool = false) {
        self.id = note.id
        self.scope = note.scope
        self.scopeLabel = note.scope.title
        self.title = note.title
        self.preview = Self.preview(note.content)
        self.relativePath = note.relativePath
        self.byteCountLabel = note.wasTruncated
            ? "\(note.byteCount) bytes, truncated"
            : "\(note.byteCount) bytes"
        let canEdit = note.scope == .global || (note.scope == .project && canEditProjectMemory)
        self.canEdit = canEdit
        self.editCommandID = canEdit ? "memory-edit:\(note.id)" : nil
        let canDelete = note.scope == .global || (note.scope == .project && canEditProjectMemory)
        self.canDelete = canDelete
        self.deleteCommandID = canDelete ? "memory-delete:\(note.id)" : nil
    }

    private static func preview(_ content: String) -> String {
        let normalized = content
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard normalized.count > 180 else { return normalized }
        let end = normalized.index(normalized.startIndex, offsetBy: 180)
        return "\(normalized[..<end])..."
    }
}
