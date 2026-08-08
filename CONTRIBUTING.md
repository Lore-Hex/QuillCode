# Contributing to Quill Cowork

Thanks for helping improve Quill Cowork. Changes should preserve its native-app advantages: fast
startup, bounded memory, crash resilience, clear approval boundaries, and predictable workflows.

## Before Opening a Pull Request

1. Start from the latest `main` and use a focused branch.
2. Follow the patterns and ownership boundaries already present in nearby code.
3. Add focused tests for changed behavior and broader coverage when a shared contract changes.
4. Keep credentials, transcripts, workspace paths, and private project data out of commits, issues,
   screenshots, fixtures, and test output.
5. Run the relevant focused tests, then the complete suite when the change affects shared or
   user-facing behavior.

The standard local checks are:

```bash
swift test
./scripts/smoke.sh
git diff --check
```

Release and updater changes should also follow the verification procedures in
[Downloadable Builds](docs/DOWNLOADS.md). UI changes should be exercised in the packaged app at
desktop and compact window sizes, with accessibility and keyboard behavior checked explicitly.

## Pull Requests

Explain the user-visible behavior, implementation boundaries, risks, and verification performed.
Keep unrelated refactors and generated churn out of the change. A maintainer adds the
`merge-train` label after required checks pass; the train serializes merges, reruns exact-`main` CI,
and republishes the tester channel from the merged commit.

By submitting a contribution, you agree that it is licensed under the repository's
[Apache License 2.0](LICENSE).
