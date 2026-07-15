import Foundation

public struct SkillCatalogError: Sendable, Hashable {
    public var path: URL
    public var message: String

    public init(path: URL, message: String) {
        self.path = path
        self.message = message
    }
}

public struct SkillCatalogSnapshot: Sendable, Hashable {
    public var skills: [SkillCatalogMetadata]
    public var errors: [SkillCatalogError]

    public init(skills: [SkillCatalogMetadata] = [], errors: [SkillCatalogError] = []) {
        self.skills = skills
        self.errors = errors
    }
}
