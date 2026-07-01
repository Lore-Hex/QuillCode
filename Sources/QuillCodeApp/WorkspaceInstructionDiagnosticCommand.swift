import Foundation

struct WorkspaceInstructionDiagnosticCommand: Equatable, Sendable {
    enum Action: Equatable, Sendable {
        case apply(keepReferenceIndex: Int)
        case resolve
        case dismiss
    }

    let action: Action
    let diagnosticID: String

    init(action: Action, diagnosticID: String) {
        self.action = action
        self.diagnosticID = diagnosticID
    }

    init?(commandID: String) {
        if let command = Self.applyCommand(commandID) {
            self = command
            return
        }
        if let diagnosticID = Self.diagnosticID(after: Self.resolvePrefix, in: commandID) {
            self.init(action: .resolve, diagnosticID: diagnosticID)
            return
        }
        if let diagnosticID = Self.diagnosticID(after: Self.dismissPrefix, in: commandID) {
            self.init(action: .dismiss, diagnosticID: diagnosticID)
            return
        }
        return nil
    }

    static func applyCommandID(diagnosticID: String, keepReferenceIndex: Int) -> String {
        "\(applyPrefix)\(keepReferenceIndex):\(diagnosticID)"
    }

    static func resolveCommandID(diagnosticID: String) -> String {
        "\(resolvePrefix)\(diagnosticID)"
    }

    static func dismissCommandID(diagnosticID: String) -> String {
        "\(dismissPrefix)\(diagnosticID)"
    }

    private static let applyPrefix = "activity-instruction-apply:"
    private static let resolvePrefix = "activity-instruction-resolve:"
    private static let dismissPrefix = "activity-instruction-dismiss:"

    private static func applyCommand(_ commandID: String) -> WorkspaceInstructionDiagnosticCommand? {
        guard commandID.hasPrefix(applyPrefix) else { return nil }
        let payload = commandID.dropFirst(applyPrefix.count)
        guard let separator = payload.firstIndex(of: ":") else { return nil }
        let rawIndex = payload[..<separator]
        let rawID = payload[payload.index(after: separator)...]
        guard let keepReferenceIndex = Int(rawIndex),
              keepReferenceIndex >= 0,
              let diagnosticID = normalizedDiagnosticID(String(rawID))
        else {
            return nil
        }
        return WorkspaceInstructionDiagnosticCommand(
            action: .apply(keepReferenceIndex: keepReferenceIndex),
            diagnosticID: diagnosticID
        )
    }

    private static func diagnosticID(after prefix: String, in commandID: String) -> String? {
        guard commandID.hasPrefix(prefix) else { return nil }
        return normalizedDiagnosticID(String(commandID.dropFirst(prefix.count)))
    }

    private static func normalizedDiagnosticID(_ diagnosticID: String) -> String? {
        let trimmedID = diagnosticID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedID.isEmpty ? nil : trimmedID
    }
}
