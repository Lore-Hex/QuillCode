import Foundation
import QuillCodeCore

/// Projects a failed turn into a compact scratch context for action-only recovery. The durable
/// thread remains untouched; the correction keeps the original request and the most recent tool
/// evidence while dropping superseded browsing attempts that encourage the model to re-plan.
enum AgentCorrectiveContext {
    static let maximumMessageCharacters = 48_000
    static let minimumRecentMessageCount = 6

    static func projected(_ thread: ChatThread) -> ChatThread {
        guard thread.messages.count > minimumRecentMessageCount else { return thread }

        let leadingSystem = thread.messages.prefix(while: { $0.role == .system })
        let body = thread.messages.dropFirst(leadingSystem.count)
        let originalRequest = body.first(where: { $0.role == .user })

        var retainedReversed: [ChatMessage] = []
        var retainedCharacters = 0
        for message in body.reversed() {
            let isOriginalRequest = message.id == originalRequest?.id
            if isOriginalRequest { continue }

            let mustKeep = retainedReversed.count < minimumRecentMessageCount
            if !mustKeep,
               retainedCharacters + message.content.count > maximumMessageCharacters {
                break
            }
            retainedReversed.append(message)
            retainedCharacters += message.content.count
        }

        var projected = thread
        var messages = Array(leadingSystem)
        if let originalRequest,
           !retainedReversed.contains(where: { $0.id == originalRequest.id }) {
            messages.append(originalRequest)
        }
        messages.append(contentsOf: retainedReversed.reversed())
        projected.messages = messages
        return projected
    }
}
