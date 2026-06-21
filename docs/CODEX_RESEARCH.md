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
