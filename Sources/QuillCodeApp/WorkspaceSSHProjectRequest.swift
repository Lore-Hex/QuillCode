import Foundation
import QuillCodeCore

public struct WorkspaceSSHProjectRequest: Sendable, Hashable {
    public var connection: ProjectConnection
    public var name: String?

    public init?(connection: ProjectConnection, name: String? = nil) {
        guard connection.kind == .ssh else { return nil }
        self.connection = connection
        self.name = name
    }
}

public enum WorkspaceSSHProjectRegistrationResult: Sendable, Hashable {
    case success(projectID: UUID)
    case failure(message: String)
}
