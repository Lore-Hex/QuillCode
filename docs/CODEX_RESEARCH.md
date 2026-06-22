# Codex Research Notes

QuillCode tracks Codex workflow parity without copying private implementation or visual trade dress. These notes capture why each feature exists and how QuillCode should implement the equivalent.

## Current Research Inputs

- Codex app: projects, worktrees, automations, Git review, in-app browser, Computer Use, artifact previews.
- Codex commands: command menu, keyboard shortcuts, thread search, slash commands.
- Sandbox and Auto-review: enforce boundaries first, route eligible review requests through a reviewer model.
- Remote connections: phone/host pairing, remote approvals, host-local files and tools.
- Plugins, skills, MCP: reusable workflows and external tools; first expose project-local manifests clearly before enabling install/process lifecycle.
- Memories and Chronicle: local recall layer, not a replacement for checked-in project rules. The first shippable slice should make loaded memory visible and auditable; explicit `/remember text` writes and explicit Forget actions are acceptable with clear transcript feedback and credential rejection before enabling autonomous writes.

## Product Translation

- QuillCode should feel like a fast native coding workspace.
- The first screen is the real workspace, not a landing page.
- A simple user request should either execute directly or show a precise review reason; it should not say “I will do it” and then stall.
- Review UI should be calm and specific. Safety language should avoid scary labels for approved low-risk commands.
- Tool outputs should end with a clear chat answer, not only raw JSON cards.
- Memory context should be inspectable from the workspace chrome. Users should be able to tell what background notes the agent can see, and the agent must treat those notes as context rather than commands.
- App-managed global memory needs reversible UX before autonomous memory is considered. Project memories are files and should stay under project ownership unless QuillCode is explicitly editing those files.
- Browser preview should give immediate inspection context even before a full native WebView exists. A bounded metadata snapshot is useful for local HTML review and avoids pretending QuillCode has loaded a signed-in browser profile.

## Claude CLI Design Review Notes

- Tool cards should have three density states: collapsed, peek, and expanded. Completed successful tools should collapse by default so the transcript reads like a conversation, while queued/running cards peek and failed/review cards stay more open for diagnosis. QuillCode now carries this as explicit surface data so native and harness renderers stay aligned.
- The top bar must use fixed-width numeric/status zones with tabular digits so token counts, model names, and connection status never cause layout jitter.
- Safety review should be inline and calm. Approved low-risk actions should read as ordinary progress, while red and modal treatment should be reserved for actual denials or destructive actions.
- MCP schemas should default to a compact name/description/argument-count presentation, with richer argument detail available on expansion. Dense schema text is useful, but it should not dominate the first view.
- Native feel depends on restraint: hairline borders over heavy shadows, short ease-out disclosure animations, optimistic message rendering, and direct keyboard access for model picker, find, stop, and command palette actions.
- The latest Claude CLI UI pass called out three structural pressure points: top-bar pill overflow should collapse into clearer model/mode/context clusters, the sidebar plus Activity pane should not consume most of the window before the transcript gets space, and the HTML harness composer needed to become a multiline textarea so Playwright parity does not lie about native composer behavior. The top bar now uses explicit identity, primary-control, context/status, and action clusters with bounded context labels, and the composer now uses textarea semantics across SwiftUI, static HTML, and the Playwright harness, with Shift+Enter for newlines and Enter to send.
- The same pass flagged renderer drift as the main architecture risk. SwiftUI and HTML need shared surface data for every visible concept, and tests should assert the data users see, not just that a tag exists. Image artifacts now follow that rule with shared type, extension, filename, and source metadata.
