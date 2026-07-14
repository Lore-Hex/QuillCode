import Foundation
import QuillCodeCore

public struct AgentImportReceipt: Codable, Sendable, Hashable {
    public var source: AgentImportSource
    public var candidateIDs: Set<String>
    public var updatedAt: Date

    public init(
        source: AgentImportSource,
        candidateIDs: Set<String> = [],
        updatedAt: Date = Date()
    ) {
        self.source = source
        self.candidateIDs = candidateIDs
        self.updatedAt = updatedAt
    }
}

public struct AgentImportReceiptStore: Sendable {
    public var fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load(source: AgentImportSource) -> AgentImportReceipt {
        guard let data = try? Data(contentsOf: fileURL),
              let receipts = try? Self.makeDecoder().decode([AgentImportReceipt].self, from: data),
              let receipt = receipts.first(where: { $0.source == source })
        else {
            return AgentImportReceipt(source: source)
        }
        return receipt
    }

    public func record(
        _ candidateIDs: Set<String>,
        source: AgentImportSource,
        at date: Date = Date()
    ) throws {
        guard !candidateIDs.isEmpty else { return }
        var receipts = loadAll()
        if let index = receipts.firstIndex(where: { $0.source == source }) {
            receipts[index].candidateIDs.formUnion(candidateIDs)
            receipts[index].updatedAt = date
        } else {
            receipts.append(AgentImportReceipt(source: source, candidateIDs: candidateIDs, updatedAt: date))
        }
        receipts.sort { $0.source.rawValue < $1.source.rawValue }
        try PrivateDirectory.ensureExists(at: fileURL.deletingLastPathComponent())
        try Self.makeEncoder().encode(receipts).write(to: fileURL, options: .atomic)
    }

    private func loadAll() -> [AgentImportReceipt] {
        guard let data = try? Data(contentsOf: fileURL),
              let receipts = try? Self.makeDecoder().decode([AgentImportReceipt].self, from: data)
        else { return [] }
        return receipts
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

enum AgentImportReceiptKey {
    static func value(for candidate: AgentImportCandidate, destinationProjectPath: String? = nil) -> String {
        guard candidate.kind.isProjectSetupItem,
              let projectPath = destinationProjectPath ?? candidate.projectPath
        else { return candidate.id }
        return "\(candidate.id)@project:\(projectPath)"
    }

    static func isFullyImported(
        _ candidate: AgentImportCandidate,
        receiptIDs: Set<String>,
        availableProjectPaths: Set<String>
    ) -> Bool {
        guard candidate.kind.isProjectSetupItem else {
            return receiptIDs.contains(candidate.id)
        }
        let targets = candidate.projectPath.map { [$0] } ?? availableProjectPaths.sorted()
        guard !targets.isEmpty else { return false }
        return targets.allSatisfy {
            receiptIDs.contains(value(for: candidate, destinationProjectPath: $0))
        }
    }
}

extension AgentImportItemKind {
    var isProjectSetupItem: Bool {
        switch self {
        case .instructions, .settings, .skills, .plugins, .mcpServers, .hooks, .slashCommands, .subagents:
            true
        case .projects, .chats:
            false
        }
    }
}
