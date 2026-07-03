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

/// An LLM client that can turn OFF Anthropic prompt-cache breakpoints on a copy of itself.
/// One-shot auxiliary call sites (context summaries, compaction, subagent workers) use this:
/// their prompts are unique and never re-sent, so a breakpoint could only ever be a cache write
/// with no read — a pure cost premium. See `TrustedRouterPromptCaching`.
public protocol PromptCacheControllableLLMClient: LLMClient {
    /// A copy of this client that never adds prompt-cache breakpoints. The receiver is unchanged.
    func disablingPromptCaching() -> Self
}

extension TrustedRouterLLMClient: PromptCacheControllableLLMClient {}

extension RetryingLLMClient: PromptCacheControllableLLMClient
where Base: PromptCacheControllableLLMClient {
    /// Disables caching on the wrapped client while keeping this wrapper's retry policy.
    public func disablingPromptCaching() -> RetryingLLMClient<Base> {
        var copy = self
        copy.base = base.disablingPromptCaching()
        return copy
    }
}

/// Returns `client` with prompt caching disabled when it supports the control, otherwise the
/// client unchanged. Lets a call site opt a one-shot auxiliary path out of caching without
/// knowing the concrete client type (e.g. a mock client in tests is passed through untouched).
public func disablingPromptCachingIfSupported(_ client: any LLMClient) -> any LLMClient {
    (client as? any PromptCacheControllableLLMClient)?.disablingPromptCaching() ?? client
}

/// Returns `client` retargeted at `modelID` when it supports model overriding and `modelID` is
/// non-empty, otherwise the client unchanged. Lets the run path pin each turn to the SELECTED
/// (per-thread) model without knowing the concrete client type — a mock client in tests, or a
/// client already on that model, is passed through untouched. This is what makes `/model` (and the
/// top-bar picker) take effect on the very next turn: the live runner's client is built once with
/// the config default, so each send must re-point it at the thread's chosen model.
public func overridingModelIfSupported(_ client: any LLMClient, modelID: String) -> any LLMClient {
    guard !modelID.isEmpty, let overridable = client as? any ModelOverridingLLMClient else {
        return client
    }
    return overridable.overridingModel(modelID)
}
