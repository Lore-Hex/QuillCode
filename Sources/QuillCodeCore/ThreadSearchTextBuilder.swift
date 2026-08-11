public enum ThreadSearchTextBuilder {
    public static let maximumCharacters = 8_000

    public static func build(
        from messages: [ChatMessage],
        maximumCharacters: Int = maximumCharacters
    ) -> String {
        guard maximumCharacters > 0 else { return "" }

        var text = ""
        text.reserveCapacity(maximumCharacters)
        var remainingCharacters = maximumCharacters
        var hasIncludedMessage = false

        for message in messages where message.role == .user || message.role == .assistant {
            guard remainingCharacters > 0 else { break }
            if hasIncludedMessage {
                text.append("\n")
                remainingCharacters -= 1
                guard remainingCharacters > 0 else { break }
            }

            let prefix = message.content.prefix(remainingCharacters)
            text.append(contentsOf: prefix)
            remainingCharacters -= prefix.count
            hasIncludedMessage = true
        }
        return text
    }
}
