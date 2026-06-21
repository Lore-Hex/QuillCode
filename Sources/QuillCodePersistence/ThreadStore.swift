import Foundation
import QuillCodeCore

public struct JSONThreadStore: Sendable {
    public var directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func save(_ thread: ChatThread) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(thread)
        try data.write(to: fileURL(for: thread.id), options: .atomic)
    }

    public func load(_ id: UUID) throws -> ChatThread {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: fileURL(for: id))
        return try decoder.decode(ChatThread.self, from: data)
    }

    public func delete(_ id: UUID) throws {
        let url = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    public func list() throws -> [ChatThread] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }
        return try urls.map { url in
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(ChatThread.self, from: Data(contentsOf: url))
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }
}
