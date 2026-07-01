import Foundation
import QuillCodeCore

enum ProjectInstructionDiagnosticReferenceBuilder {
    static func reference(
        for instruction: ProjectInstruction,
        match: ProjectInstructionSemanticMatch? = nil,
        role: String,
        suggestedAction: String
    ) -> ProjectInstructionDiagnosticSourceReference {
        ProjectInstructionDiagnosticSourceReference(
            path: instruction.path,
            lineNumber: match?.lineNumber ?? 1,
            role: role,
            excerpt: match?.excerpt ?? firstContentLine(instruction.content),
            suggestedAction: suggestedAction
        )
    }

    private static func firstContentLine(_ content: String) -> String {
        content
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "Start of instruction file"
    }
}
