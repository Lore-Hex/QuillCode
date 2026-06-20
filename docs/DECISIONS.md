# QuillCode Decisions

## 2026-06-20

- Product and repository name: **QuillCode**.
- License: Apache 2.0.
- Default model: `trustedrouter/fusion`.
- Auth: TrustedRouter OAuth first; hidden developer override for API key/base URL.
- Tool modes: `Read-only`, `Review`, `Auto`; do not use the label `Full Access`.
- Auto reviewer: primary `glm-5.2`, fallback `kimi-k2.6`.
- First implementation uses a deterministic mock LLM so tests do not require network or credits.
- Live TrustedRouter mode is exposed through `quill-code --live`; native UI should use the same `LLMClient` and `SafetyModelClient` protocols.
- QuillUI is the UI direction, but core tests must not depend on a dirty local QuillUI checkout.
- Platform-specific code belongs in adapter packages, not the app target.
- The first desktop executable is `quill-code-desktop`, built with SwiftUI over the same `WorkspaceSurface` contract used by the HTML/Playwright harness. This keeps native UI work testable before the full QuillUI adapter exists.
- Desktop runtime selection defaults to mock LLM for no-key demos, switches to live TrustedRouter when an environment or stored secret key exists, and supports `QUILLCODE_USE_MOCK_LLM=true` for deterministic test runs.
- The desktop model picker is data-driven from the TrustedRouter catalog. It keeps `trustedrouter/fusion` as the deterministic fallback, groups options by category, and refreshes live catalog data only when an env or stored key exists.
- The first project UX is a native project rail backed by explicit selected-project state. The desktop app seeds the launch working directory as the initial project; native folder picking and a persisted project registry remain separate adapter milestones.
