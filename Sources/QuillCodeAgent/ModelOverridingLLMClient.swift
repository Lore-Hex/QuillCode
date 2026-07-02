import Foundation
import QuillCodeCore

/// An LLM client that can retarget a copy of itself at a different model. Auxiliary call sites
/// (context summaries, compaction) use this to send housekeeping calls to a cheap model without
/// touching the client — or the model — the main conversation turn runs on.
public protocol ModelOverridingLLMClient: LLMClient {
    /// Returns a copy of this client whose requests go to `modelID`. The receiver is unchanged.
    func overridingModel(_ modelID: String) -> Self
}

extension TrustedRouterLLMClient: ModelOverridingLLMClient {
    public func overridingModel(_ modelID: String) -> TrustedRouterLLMClient {
        var copy = self
        copy.model = modelID
        return copy
    }
}

extension RetryingLLMClient: ModelOverridingLLMClient where Base: ModelOverridingLLMClient {
    /// Retargets the wrapped client while keeping this wrapper's retry policy and callbacks.
    public func overridingModel(_ modelID: String) -> RetryingLLMClient<Base> {
        var copy = self
        copy.base = base.overridingModel(modelID)
        return copy
    }
}
