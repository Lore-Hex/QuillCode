import Foundation

/// Raw model-visible history that is intentionally absent from the user-facing transcript.
///
/// `afterMessageID == nil` places an item before the first visible message. Otherwise the item is
/// replayed immediately after the referenced message. Array order resolves multiple items at the
/// same boundary and therefore preserves each app-server injection request exactly.
public struct ThreadModelContextItem: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public var afterMessageID: UUID?
    public var responseItem: QuillJSONValue

    public init(
        id: UUID = UUID(),
        afterMessageID: UUID?,
        responseItem: QuillJSONValue
    ) {
        self.id = id
        self.afterMessageID = afterMessageID
        self.responseItem = responseItem
    }
}
