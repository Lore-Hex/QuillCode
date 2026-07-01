import Foundation

public extension ProjectRef {
    var dismissedInstructionDiagnosticIDs: Set<String> {
        instructionDiagnosticIDs(with: .dismissed)
    }

    var resolvedInstructionDiagnosticIDs: Set<String> {
        instructionDiagnosticIDs(with: .resolved)
    }

    @discardableResult
    mutating func dismissInstructionDiagnostic(
        id rawID: String,
        at date: Date = Date()
    ) -> Bool {
        recordInstructionDiagnostic(id: rawID, disposition: .dismissed, at: date)
    }

    @discardableResult
    mutating func resolveInstructionDiagnostic(
        id rawID: String,
        at date: Date = Date()
    ) -> Bool {
        recordInstructionDiagnostic(id: rawID, disposition: .resolved, at: date)
    }

    private func instructionDiagnosticIDs(
        with disposition: ProjectInstructionDiagnosticDisposition
    ) -> Set<String> {
        Set(instructionDiagnosticResolutions
            .filter { $0.disposition == disposition }
            .map(\.diagnosticID))
    }

    private mutating func recordInstructionDiagnostic(
        id rawID: String,
        disposition: ProjectInstructionDiagnosticDisposition,
        at date: Date
    ) -> Bool {
        guard let id = ProjectInstructionDiagnosticResolution.normalizedDiagnosticID(rawID) else {
            return false
        }
        let resolution = ProjectInstructionDiagnosticResolution(
            diagnosticID: id,
            disposition: disposition,
            updatedAt: date
        )
        if let index = instructionDiagnosticResolutions.firstIndex(where: { $0.diagnosticID == id }) {
            guard instructionDiagnosticResolutions[index].disposition != disposition else {
                return false
            }
            instructionDiagnosticResolutions[index] = resolution
        } else {
            instructionDiagnosticResolutions.append(resolution)
        }
        instructionDiagnosticResolutions = Self.normalizedInstructionDiagnosticResolutions(
            instructionDiagnosticResolutions
        )
        return true
    }
}

extension ProjectRef {
    static func normalizedInstructionDiagnosticResolutions(
        _ resolutions: [ProjectInstructionDiagnosticResolution]
    ) -> [ProjectInstructionDiagnosticResolution] {
        var latestByID: [String: ProjectInstructionDiagnosticResolution] = [:]
        for rawResolution in resolutions {
            guard let diagnosticID = ProjectInstructionDiagnosticResolution
                .normalizedDiagnosticID(rawResolution.diagnosticID)
            else { continue }
            var resolution = rawResolution
            resolution.diagnosticID = diagnosticID
            if let current = latestByID[diagnosticID] {
                if current.updatedAt <= resolution.updatedAt {
                    latestByID[diagnosticID] = resolution
                }
            } else {
                latestByID[resolution.diagnosticID] = resolution
            }
        }
        return latestByID.values.sorted {
            if $0.updatedAt == $1.updatedAt {
                return $0.diagnosticID < $1.diagnosticID
            }
            return $0.updatedAt > $1.updatedAt
        }
    }
}

public enum ProjectInstructionDiagnosticDisposition: String, Codable, Sendable, Hashable {
    case dismissed
    case resolved
}

public struct ProjectInstructionDiagnosticResolution: Codable, Sendable, Hashable, Identifiable {
    public var id: String { diagnosticID }
    public var diagnosticID: String
    public var disposition: ProjectInstructionDiagnosticDisposition
    public var updatedAt: Date

    public init(
        diagnosticID: String,
        disposition: ProjectInstructionDiagnosticDisposition = .dismissed,
        updatedAt: Date = Date()
    ) {
        self.diagnosticID = Self.normalizedDiagnosticID(diagnosticID) ?? ""
        self.disposition = disposition
        self.updatedAt = updatedAt
    }

    public static func normalizedDiagnosticID(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
