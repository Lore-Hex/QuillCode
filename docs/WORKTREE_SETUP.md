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
When `[worktree_setup]` is present, an invalid or missing script path is reported in the new task with repair guidance instead of silently falling back to another script. Without explicit configuration, projects that do not contain one of the conventional setup scripts remain a quiet no-op.

## Named Environments

Projects can offer named setup environments in the New Worktree Task dialog:

```toml
[worktree_setup]
default_environment = "development"

[local_environments.development]
title = "Development"
description = "Install dependencies for app development."

[local_environments.ci]
title = "CI"
script = "scripts/setup-ci.sh"
```

When paths are omitted, `development` resolves these files in order:

1. `.quillcode/environments/development/setup.macos.sh` on macOS
2. `.quillcode/environments/development/setup.linux.sh` on Linux
3. `.quillcode/environments/development/setup.sh` as the fallback

The task dialog offers **Automatic**, **No setup**, and every configured environment. Automatic uses `default_environment` when configured; otherwise it preserves the project-wide setup behavior described above. The exact selection is stored with the task. A named environment with invalid paths or missing from the materialized checkout fails visibly instead of silently running another environment.

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
