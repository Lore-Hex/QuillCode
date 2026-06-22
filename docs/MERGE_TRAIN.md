# Merge Train

QuillCode uses a small GitHub Actions merge train so multiple agents can work in parallel without racing direct pushes to `main`.

## How Agents Should Use It

1. Open a pull request targeting `main`.
2. Wait for `CI` to pass.
3. Add the `merge-train` label when the PR is ready to ship. The `automerge` label is accepted as an alias.
4. Add `do-not-merge` to pause a PR without removing it from review.

The train processes only the oldest eligible PR at a time. It ignores draft PRs and PRs labeled `do-not-merge`.

## What The Train Checks

- The PR must target `main`.
- The PR must have `merge-train` or `automerge`.
- All status checks except the train workflow itself must be successful or skipped.
- A behind branch is updated first, then the train waits for fresh CI.
- Only one train run can execute at a time.

When the train head is ready, it merges with a squash merge and deletes the source branch.

## Required Repository Settings

The workflow is most useful when `main` is protected:

- Require status checks before merging.
- Require branches to be up to date before merging.
- Required checks: `swift`, `linux-swift`, `playwright`, and `smoke`.
- Require conversation resolution.
- Allow auto-merge and delete branches on merge.

CI also runs on GitHub `merge_group` events so native GitHub Merge Queue can be enabled later without changing the test workflow.

## Manual Controls

Run **Merge Train** manually from the Actions tab to kick the queue. It also runs after CI completes, on relevant PR label/synchronize events, and every 10 minutes as a fallback.
