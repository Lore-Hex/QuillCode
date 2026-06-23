import Foundation

enum WorkspaceMemoryErrorMessageBuilder {
    static func userFacingMessage(for error: any Error) -> String {
        if let localized = (error as? any LocalizedError)?.errorDescription,
           !localized.isEmpty {
            return localized
        }
        return String(describing: error)
    }
}
