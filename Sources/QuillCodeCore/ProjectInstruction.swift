import Foundation

public struct ProjectInstruction: Codable, Sendable, Hashable, Identifiable {
    public var id: String { path }
    public var path: String
    public var scopePath: String
    public var title: String
    public var content: String
    public var byteCount: Int
    public var wasTruncated: Bool

    public init(
        path: String,
        scopePath: String? = nil,
        title: String,
        content: String,
        byteCount: Int,
        wasTruncated: Bool = false
    ) {
        self.path = path
        self.scopePath = scopePath ?? Self.scopePath(for: path)
        self.title = title
        self.content = content
        self.byteCount = byteCount
        self.wasTruncated = wasTruncated
    }

    public var scopeLabel: String {
        Self.scopeLabel(for: scopePath)
    }

    public static func scopeLabel(for scopePath: String) -> String {
        scopePath == "." ? "whole project" : "\(scopePath)/**"
    }

    public static func scopePath(for instructionPath: String) -> String {
        let components = instructionPath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard components.count > 1 else { return "." }

        let suffix = Array(components.suffix(2))
        if suffix == [".quillcode", "rules.md"]
            || suffix == [".quillcode", "instructions.md"] {
            let scope = components.dropLast(2).joined(separator: "/")
            return scope.isEmpty ? "." : scope
        }

        let scope = components.dropLast().joined(separator: "/")
        return scope.isEmpty ? "." : scope
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case scopePath
        case title
        case content
        case byteCount
        case wasTruncated
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.path = try container.decode(String.self, forKey: .path)
        self.scopePath = try container.decodeIfPresent(String.self, forKey: .scopePath)
            ?? Self.scopePath(for: path)
        self.title = try container.decode(String.self, forKey: .title)
        self.content = try container.decode(String.self, forKey: .content)
        self.byteCount = try container.decode(Int.self, forKey: .byteCount)
        self.wasTruncated = try container.decodeIfPresent(Bool.self, forKey: .wasTruncated) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encode(scopePath, forKey: .scopePath)
        try container.encode(title, forKey: .title)
        try container.encode(content, forKey: .content)
        try container.encode(byteCount, forKey: .byteCount)
        try container.encode(wasTruncated, forKey: .wasTruncated)
    }
}
