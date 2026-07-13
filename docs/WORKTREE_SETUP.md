# Worktree Setup

QuillCode can prepare each new managed Worktree task automatically. Add one of these scripts to the project:

1. `.quillcode/setup.macos.sh` on macOS
2. `.quillcode/setup.linux.sh` on Linux
3. `.quillcode/setup.sh` as the cross-platform fallback

The platform script wins when both it and the fallback exist. QuillCode resolves the script from the newly created checkout after local task state has transferred, then runs it from that worktree through the normal shell tool-card path. Output, errors, timeouts, and reruns stay visible in the task transcript. A failed setup keeps the worktree available for diagnosis. Setup allows up to 30 minutes by default; use sidecar metadata to choose a shorter bound.

## Custom Paths

Override the default paths in `.quillcode/config.toml`:

```toml
[worktree_setup]
script = "scripts/setup/default.sh"
macos = "scripts/setup/macos.sh"
linux = "scripts/setup/linux.sh"
```

Paths must be relative `.sh` files inside the worktree. Absolute paths, parent traversal, and symlink escapes are ignored.

## Metadata

A same-name JSON sidecar can set environment variables, a working directory, and a timeout using the same policy as local environment actions:

```json
{
  "environment": {
    "QUILL_ENV": "development"
  },
  "workingDirectory": "app",
  "timeoutSeconds": 900
}
```

For `.quillcode/setup.macos.sh`, name the sidecar `.quillcode/setup.macos.json`. Working directories must resolve inside the worktree, timeouts must be 1-1800 seconds, and environment values are redacted from persisted tool-card input.
