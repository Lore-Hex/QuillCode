# Security Policy

## Supported Versions

Security fixes target the latest published stable release and the moving `tester-latest` build.
Older tester builds should update automatically or be replaced with the current download before a
report is reproduced.

## Reporting a Vulnerability

Do not open a public issue for a suspected vulnerability. Use GitHub's
[private vulnerability report](https://github.com/Lore-Hex/QuillCode/security/advisories/new) so
details stay restricted to repository maintainers while the report is investigated.

Include, when available:

- the affected Quill Cowork version, build, channel, and platform
- the affected boundary, such as updater, command execution, approvals, workspace isolation,
  authentication, Computer Use, plugins, hooks, MCP, or remote access
- reproduction steps or a minimal proof of concept
- the security impact and any prerequisites
- sanitized logs, screenshots, or crash details

Never submit live credentials, API keys, tokens, private source code, transcripts, workspace data,
or customer data. Revoke any credential that may already have been exposed.

Maintainers will coordinate remediation and disclosure with the reporter. Please avoid public
disclosure until a fix is available and affected users have had a reasonable opportunity to update.
The project does not currently operate a paid bug-bounty program.
