import QuillCodeCore
import TrustedRouter

/// Fail-closed provider requirements attached to every TrustedRouter inference request.
public enum TrustedRouterRequestPrivacy: Sendable, Hashable {
    case standard
    case confidential(jurisdiction: TrustedRouterJurisdiction)

    public var providerPayload: [String: String]? {
        switch self {
        case .standard:
            nil
        case .confidential(let jurisdiction):
            [
                "data_collection": "deny",
                "min_privacy": "confidential",
                "jurisdiction": jurisdiction.rawValue
            ]
        }
    }

    var providerPreferences: ProviderPreferences? {
        switch self {
        case .standard:
            nil
        case .confidential(let jurisdiction):
            ProviderPreferences(
                dataCollection: "deny",
                minimumPrivacy: "confidential",
                jurisdiction: jurisdiction.rawValue
            )
        }
    }
}
