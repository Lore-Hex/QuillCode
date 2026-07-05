import Foundation
import QuillCodeCore

enum SlashModelCommandParser {
    private static let usage = "Usage: /model nike or /model provider/model"
    private static let retiredRawModelMessage =
        "The raw synth model type is no longer a named endpoint. Use /model nike, /model prometheus, or a provider/model from TrustedRouter."

    static func parse(_ argument: String) -> SlashCommand {
        let model = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        if model.isEmpty {
            return .invalid(usage)
        }
        if TrustedRouterDefaults.isRetiredRawModelID(model) {
            return .invalid(retiredRawModelMessage)
        }
        return .model(model)
    }
}
