import Foundation
import QuillCodeCore

enum WorkspaceSubagentApprovalAction: String, Sendable, Hashable {
    case approve
    case reject
}

struct WorkspaceSubagentApprovalCommand: Sendable, Hashable {
    private static let prefix = "subagent-approval"

    var action: WorkspaceSubagentApprovalAction
    var runID: String
    var requestID: String

    init?(commandID: String) {
        let parts = commandID.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4,
              parts[0] == Self.prefix,
              let action = WorkspaceSubagentApprovalAction(rawValue: parts[1]),
              UUID(uuidString: parts[2]) != nil,
              Self.isOpaqueID(parts[3])
        else { return nil }
        self.action = action
        self.runID = parts[2]
        self.requestID = parts[3]
    }

    static func approveCommandID(for gate: SubagentApprovalGate) -> String {
        commandID(action: .approve, gate: gate)
    }

    static func rejectCommandID(for gate: SubagentApprovalGate) -> String {
        commandID(action: .reject, gate: gate)
    }

    private static func commandID(
        action: WorkspaceSubagentApprovalAction,
        gate: SubagentApprovalGate
    ) -> String {
        "\(prefix):\(action.rawValue):\(gate.runID):\(gate.requestID)"
    }

    static func isValid(_ gate: SubagentApprovalGate) -> Bool {
        UUID(uuidString: gate.runID) != nil && isOpaqueID(gate.requestID)
    }

    private static func isOpaqueID(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 96 else { return false }
        return value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
        }
    }
}
