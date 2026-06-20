# QuillCode Decisions

## 2026-06-20

- Product and repository name: **QuillCode**.
- License: Apache 2.0.
- Default model: `trustedrouter/fusion`.
- Auth: TrustedRouter OAuth first; hidden developer override for API key/base URL.
- Tool modes: `Read-only`, `Review`, `Auto`; do not use the label `Full Access`.
- Auto reviewer: primary `glm-5.2`, fallback `kimi-k2.6`.
- First implementation uses a deterministic mock LLM so tests do not require network or credits.
- QuillUI is the UI direction, but core tests must not depend on a dirty local QuillUI checkout.
- Platform-specific code belongs in adapter packages, not the app target.

