import QuillCodeCore

struct ProjectInstructionDiagnostic: Sendable, Hashable, Identifiable {
    var id: String
    var title: String
    var detail: String
    var statusLabel: String
}

enum ProjectInstructionDiagnosticsBuilder {
    static func diagnostics(for instructions: [ProjectInstruction]) -> [ProjectInstructionDiagnostic] {
        duplicateScopeDiagnostics(for: instructions) + nestedOverrideDiagnostics(for: instructions)
    }

    private static func duplicateScopeDiagnostics(for instructions: [ProjectInstruction]) -> [ProjectInstructionDiagnostic] {
        orderedScopeGroups(for: instructions).compactMap { scopePath, scopedInstructions in
            guard scopedInstructions.count > 1 else { return nil }
            return ProjectInstructionDiagnostic(
                id: "instruction-duplicate-scope-\(normalizedID(scopePath))",
                title: "Shared instruction scope",
                detail: "\(ProjectInstruction.scopeLabel(for: scopePath)): \(pathList(scopedInstructions))",
                statusLabel: "review"
            )
        }
    }

    private static func nestedOverrideDiagnostics(for instructions: [ProjectInstruction]) -> [ProjectInstructionDiagnostic] {
        orderedScopeGroups(for: instructions).compactMap { scopePath, scopedInstructions in
            guard scopePath != "." else { return nil }
            let broaderInstructions = instructions.filter { isBroaderScope($0.scopePath, than: scopePath) }
            guard !broaderInstructions.isEmpty else { return nil }

            return ProjectInstructionDiagnostic(
                id: "instruction-nested-override-\(normalizedID(scopePath))",
                title: "Nested instruction override",
                detail: "\(ProjectInstruction.scopeLabel(for: scopePath)) from \(pathList(scopedInstructions)) may override \(pathList(broaderInstructions))",
                statusLabel: "scope"
            )
        }
    }

    private static func orderedScopeGroups(
        for instructions: [ProjectInstruction]
    ) -> [(scopePath: String, instructions: [ProjectInstruction])] {
        var order: [String] = []
        var grouped: [String: [ProjectInstruction]] = [:]

        for instruction in instructions {
            if grouped[instruction.scopePath] == nil {
                order.append(instruction.scopePath)
            }
            grouped[instruction.scopePath, default: []].append(instruction)
        }

        return order.map { scopePath in
            (scopePath: scopePath, instructions: grouped[scopePath] ?? [])
        }
    }

    private static func isBroaderScope(_ candidate: String, than scopePath: String) -> Bool {
        if candidate == "." {
            return scopePath != "."
        }
        return scopePath.hasPrefix(candidate + "/")
    }

    private static func pathList(_ instructions: [ProjectInstruction]) -> String {
        instructions.map(\.path).joined(separator: ", ")
    }

    private static func normalizedID(_ scopePath: String) -> String {
        scopePath == "." ? "root" : scopePath.replacingOccurrences(of: "/", with: "-")
    }
}
