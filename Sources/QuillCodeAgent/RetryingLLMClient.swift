import Foundation
import QuillCodeCore

/// Sleeps for a duration. Injected into the retry decorator so tests can run instantly and assert the
/// exact backoff durations that were requested, rather than actually waiting.
public protocol RetrySleeper: Sendable {
    func sleep(_ duration: Duration) async throws
}

public struct SystemRetrySleeper: RetrySleeper {
    public init() {}
    public func sleep(_ duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

/// Wraps an LLM client so a transient TrustedRouter/network blip on a model call is retried with
/// backoff instead of killing the whole run. This is THE fix for the most common way an unattended
/// run dies silently: a momentary 429/5xx or a dropped connection on tool-step 4 of 6, burning all the
/// prior tool work on a run you are not watching.
///
/// SAFETY: retry is applied only to the `async throws` that OBTAINS the result/stream — for the
/// TrustedRouter client the HTTP status error is thrown there, before any token is emitted, so a retry
/// can never double-emit streamed content. A failure that happens mid-stream (after tokens have been
/// yielded) lives inside the returned `AsyncThrowingStream` and is deliberately NOT wrapped, so it
/// surfaces to the caller un-retried. A `CancellationError` is never retried (it is the user stopping).
public struct RetryingLLMClient<Base: UsageStreamingLLMClient>: UsageStreamingLLMClient {
    public var base: Base
    public var policy: RetryBackoffPolicy
    public var sleeper: any RetrySleeper
    public var jitter: @Sendable () -> Double
    /// Fired just before each backoff sleep, so the wiring layer can surface a "Self-healing: retrying"
    /// notice. Arguments: the retry number (1-based), the failure class, and the delay about to elapse.
    public var onRetry: @Sendable (Int, TransientFailureClass, Duration) -> Void

    public init(
        base: Base,
        policy: RetryBackoffPolicy = RetryBackoffPolicy(),
        sleeper: any RetrySleeper = SystemRetrySleeper(),
        jitter: @escaping @Sendable () -> Double = { Double.random(in: 0...1) },
        onRetry: @escaping @Sendable (Int, TransientFailureClass, Duration) -> Void = { _, _, _ in }
    ) {
        self.base = base
        self.policy = policy
        self.sleeper = sleeper
        self.jitter = jitter
        self.onRetry = onRetry
    }

    public func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        try await withRetry { try await base.nextAction(thread: thread, userMessage: userMessage, tools: tools) }
    }

    public func actionTextStream(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AsyncThrowingStream<String, Error> {
        try await withRetry { try await base.actionTextStream(thread: thread, userMessage: userMessage, tools: tools) }
    }

    public func actionEventStream(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AsyncThrowingStream<AgentTextStreamEvent, Error> {
        try await withRetry { try await base.actionEventStream(thread: thread, userMessage: userMessage, tools: tools) }
    }

    private func withRetry<T>(_ operation: @Sendable () async throws -> T) async throws -> T {
        var attempt = 0
        while true {
            do {
                return try await operation()
            } catch {
                let failureClass = RetryClassifier.classify(error)
                let retryNumber = attempt + 1
                // Non-transient, or out of budget: surface the (last) error unchanged.
                guard failureClass != .none, retryNumber < policy.maxAttempts else { throw error }
                // Honor a cancellation that arrived while we were failing, before sleeping.
                try Task.checkCancellation()
                let delay = policy.delay(
                    forAttempt: attempt,
                    jitter: jitter(),
                    rateLimit: RetryClassifier.rateLimitDetails(error)
                )
                onRetry(retryNumber, failureClass, delay)
                try await sleeper.sleep(delay)
                try Task.checkCancellation()
                attempt = retryNumber
            }
        }
    }
}
