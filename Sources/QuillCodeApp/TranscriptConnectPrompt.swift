import Foundation

/// The first-run "connect your account" gate shown in the empty transcript when the app has no
/// TrustedRouter credential yet. Its whole reason to exist: a brand-new user must not land in a chat
/// that silently does nothing. Sign-in already exists (the TrustedRouter OAuth flow) but lives buried
/// in Settings — so a keyless user types into a composer whose send throws `missingAPIKey` deep in the
/// LLM client, with nothing surfaced. This puts the sign-in front and center, right where they'd type.
///
/// A pure value type (no SwiftUI) so the "show it or not" decision and its copy are unit-testable
/// without rendering a view. `make` returns nil once a credential is stored, so a returning/connected
/// user never sees the gate.
public struct TranscriptConnectPrompt: Equatable, Sendable {
    public var signInURL: String
    public var accountURL: String

    public static let title = "Connect TrustedRouter to start"
    public static let subtitle =
        "QuillCode runs on TrustedRouter — private, attested inference. Sign in to pick a model and "
        + "start coding. Your keys never touch the page."
    public static let signInButtonTitle = "Sign in with TrustedRouter"
    public static let createAccountTitle = "Create an account"
    public static let developerKeyTitle = "Use a developer key"
    public static let defaultAccountURL = "https://trustedrouter.com"
    /// The three-beat "what happens next" reassurance under the button.
    public static let steps = ["Sign in", "Pick a model", "Start coding"]

    public init(signInURL: String, accountURL: String = TranscriptConnectPrompt.defaultAccountURL) {
        self.signInURL = signInURL
        self.accountURL = accountURL
    }

    /// The gate to show, or nil when a credential is already stored (connected users skip onboarding).
    public static func make(hasStoredAPIKey: Bool, signInURL: String) -> TranscriptConnectPrompt? {
        guard !hasStoredAPIKey else { return nil }
        return TranscriptConnectPrompt(signInURL: signInURL)
    }
}
