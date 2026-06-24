import Foundation

enum SlashModelCommandParser {
    private static let usage = "Usage: /model /synth or /model provider/model"

    static func parse(_ argument: String) -> SlashCommand {
        let model = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.isEmpty ? .invalid(usage) : .model(model)
    }
}
