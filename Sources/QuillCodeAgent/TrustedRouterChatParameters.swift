public enum TrustedRouterChatParameters {
    public static let deepSeekV4Flash0731Model = "deepseek/deepseek-v4-flash-0731"

    public static var jsonObjectResponse: [String: Any] {
        ["response_format": ["type": "json_object"]]
    }

    /// Agent turns need an action, not an unbounded hidden chain of thought. This exact route
    /// defaults to reasoning and can otherwise spend the full Cowork deadline before emitting its
    /// JSON action. TrustedRouter accepts the OpenAI-compatible `reasoning_effort` control for the
    /// route; keep the exception model-scoped so unrelated providers retain their native defaults.
    public static func agentActionResponse(model: String) -> [String: Any] {
        var parameters = jsonObjectResponse
        if model == deepSeekV4Flash0731Model {
            parameters["reasoning_effort"] = "none"
        }
        return parameters
    }
}
