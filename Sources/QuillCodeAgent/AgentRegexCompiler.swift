import Foundation

enum AgentRegexCompiler {
    static func compile(_ pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            preconditionFailure(
                "Invalid static regular expression \(pattern): \(error.localizedDescription)"
            )
        }
    }

    static func compile(pattern: String) -> NSRegularExpression {
        compile(pattern)
    }
}
