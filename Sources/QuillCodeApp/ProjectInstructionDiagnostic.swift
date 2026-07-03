struct ProjectInstructionDiagnostic: Sendable, Hashable, Identifiable {
    var id: String
    var title: String
    var detail: String
    var statusLabel: String
    var sourceReferences: [ProjectInstructionDiagnosticSourceReference]
    var resolutionHint: String

    var locationSummary: String {
        sourceReferences.map(\.locationLabel).joined(separator: ", ")
    }

    var isConflict: Bool {
        statusLabel == ProjectInstructionDiagnosticStatusLabel.conflict
    }

    var isDuplicateScope: Bool {
        statusLabel == ProjectInstructionDiagnosticStatusLabel.review
            && id.hasPrefix("instruction-duplicate-scope-")
    }

    var isNestedOverlap: Bool {
        statusLabel == ProjectInstructionDiagnosticStatusLabel.scope
            && id.hasPrefix("instruction-nested-overlap-")
    }

    var isExplicitNestedOverride: Bool {
        statusLabel == ProjectInstructionDiagnosticStatusLabel.scope
            && id.hasPrefix("instruction-nested-override-")
    }

    init(
        id: String,
        title: String,
        detail: String,
        statusLabel: String,
        sourceReferences: [ProjectInstructionDiagnosticSourceReference] = [],
        resolutionHint: String = ""
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.statusLabel = statusLabel
        self.sourceReferences = sourceReferences
        self.resolutionHint = resolutionHint
    }
}

enum ProjectInstructionDiagnosticStatusLabel {
    static let review = "review"
    static let scope = "scope"
    static let conflict = "conflict"
}

struct ProjectInstructionDiagnosticSourceReference: Sendable, Hashable {
    var path: String
    var lineNumber: Int
    var role: String
    var excerpt: String
    var suggestedAction: String

    var locationLabel: String {
        "\(path):\(lineNumber)"
    }

    init(
        path: String,
        lineNumber: Int,
        role: String,
        excerpt: String,
        suggestedAction: String = ""
    ) {
        self.path = path
        self.lineNumber = max(1, lineNumber)
        self.role = role
        self.excerpt = excerpt
        self.suggestedAction = suggestedAction
    }
}
