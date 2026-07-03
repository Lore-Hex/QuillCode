enum ProjectInstructionDiagnosticLineRemovalKind: CaseIterable {
    case nestedOverlap
    case nestedOverride

    static func matching(_ diagnostic: ProjectInstructionDiagnostic) -> Self? {
        allCases.first { $0.matches(diagnostic) }
    }

    var referenceRole: String {
        switch self {
        case .nestedOverlap:
            ProjectInstructionDiagnosticReferenceRole.repeatedNestedGuidance
        case .nestedOverride:
            ProjectInstructionDiagnosticReferenceRole.nestedOverride
        }
    }

    func matches(_ diagnostic: ProjectInstructionDiagnostic) -> Bool {
        switch self {
        case .nestedOverlap:
            diagnostic.isNestedOverlap
        case .nestedOverride:
            diagnostic.isExplicitNestedOverride
        }
    }

    func actionTitle(path: String) -> String {
        switch self {
        case .nestedOverlap:
            "Remove repeated lines from \(path)"
        case .nestedOverride:
            "Remove override lines from \(path)"
        }
    }

    func summary(path: String) -> String {
        switch self {
        case .nestedOverlap:
            "Remove repeated broad guidance from \(path)."
        case .nestedOverride:
            "Remove explicit nested override language from \(path)."
        }
    }
}
