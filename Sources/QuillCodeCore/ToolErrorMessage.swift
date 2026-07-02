import Foundation

/// Renders a thrown error as the message the model sees on the tool-result path.
///
/// `String(describing:)` on a Foundation error produces an `Error Domain=… Code=…` dump, and on a
/// bare `LocalizedError` just the case name — both waste model recovery turns. Prefer the error's
/// own human-readable message when it has one, and keep `String(describing:)` as the fallback so
/// the repo's `CustomStringConvertible` error enums render exactly as before.
public enum ToolErrorMessage {
    public static func describe(_ error: any Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription,
           !localized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return localized
        }
        if isFoundationError(error) {
            return error.localizedDescription
        }
        return String(describing: error)
    }

    private static func isFoundationError(_ error: any Error) -> Bool {
        type(of: error) is NSError.Type
            || error is CocoaError
            || error is POSIXError
            || error is URLError
    }
}
