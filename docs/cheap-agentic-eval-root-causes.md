# Cheap Agentic Eval Root Causes

Date: 2026-08-06

## Evidence

- Baseline manifest:
  `.build/quillcode-validation/cheap-agentic-evals/deepseek-v4-flash-0731-20260806-0241/manifest.json`
- Targeted two-trial rerun:
  `.build/quillcode-validation/cheap-agentic-evals/root-fix-20260806-0251/manifest.json`
- Packaged UI model: `deepseek/deepseek-v4-flash-0731`

The baseline passed 10 of 12 cases in trial 1 and 11 of 12 in trial 2. The
targeted rerun passed all three affected or related cases in both trials.

## Redaction Score

1. Why did the case fail? The output file did not match the expected bytes.
2. Why did the bytes differ? The generated file omitted one final newline.
3. Why was that scored as wrong? The grader compared raw bytes.
4. Why was raw equality too strict? The task required exact logical lines, not
   a particular end-of-file newline convention.
5. Why did this escape catalog validation? The runner had no line-semantic text
   grader, so the case reused the stricter file grader.

Root fixes: add `text_file_lines_equal`, use it for the redaction case, and
pin that contract in parity tests.

## Traversal Repair

1. Why did the case fail? The test command ran before the requested repair.
2. Why did only the test run? Immediate-action preflight extracted the command
   from the multi-step prompt.
3. Why was the prompt classified as immediate? Its actions were separated by
   sentence punctuation instead of an enumerated list, `then`, or `and`.
4. Why was that pattern absent? The multi-step gate covered several connectors
   but did not detect a new sentence beginning with another action verb.
5. Why did this escape tests? There was no exact regression for
   `Fix ... . Run ...` while retaining the short `Run ... . Report ...`
   fast path.

Root fixes: detect sentence-separated action continuations before immediate
command extraction, and test both the multi-step rejection and terse-command
acceptance paths.

## Packaged UI File Read

1. Why did the UI task fail to answer? The local file-read tool never returned.
2. Why did the underlying POSIX `open` block? The packaged app did not have a
   current macOS user-selected-folder grant for the persisted project under
   `Documents`.
3. Why was the grant unavailable after launch? The project persisted only its
   pathname; the picker grant was process-scoped and was neither bookmarked nor
   restored.
4. Why did the desktop app omit restoration? Its project model represented a
   location but not the operating-system capability lifecycle: retain, restore,
   stale-bookmark renewal, and release.
5. Why did this escape tests? CLI and unit tests inherited terminal filesystem
   access, while packaged UI coverage did not reopen a persisted project after
   a clean app relaunch.

Root fixes: persist a security-scoped bookmark when the picker imports a local
project; restore access before metadata scans; renew stale bookmarks; reject
corrupt or path-mismatched bookmarks; and stop and prune access when a project
is removed. Unit and parity tests pin those lifecycle requirements.

The folder-picker experiment confirmed the cause: granting the app access made
the exact mixed-domain UI task complete immediately with the expected JSON.
The POSIX `EINTR` retry, detached synchronous tool execution, and cached menu
icon remain useful robustness fixes, but they do not substitute for restoring
the macOS security-scoped capability. Final verification reopened the packaged
app without granting access a second time; the completed read, artifact preview,
and expected answer were immediately available and interactive.

## Persisted Artifact Preview At Startup

1. Why could the relaunched app still freeze? Transcript projection tried to
   build a text preview for a persisted local artifact on the main thread.
2. Why did preview construction block? The preview parser synchronously opened
   a file under a managed project root before that root had active security-
   scoped access.
3. Why could projection attempt that open? Artifact rendering treated a valid
   pathname as sufficient authority to read local content.
4. Why was authority absent from the renderer contract? Bookmark ownership
   lived only in the desktop project coordinator, while shared artifact
   surfaces had no readable-root policy.
5. Why did this escape tests? Preview tests covered artifact type and rendering,
   but not a clean relaunch with persisted transcript artifacts and an inactive
   macOS folder capability.

Root fixes: restore bookmarks before initial transcript projection; publish the
managed and currently readable project roots to a thread-safe preview access
policy; prevent text, image, HTML, and document preview builders from opening
unauthorized local files; preserve the artifact link and generic card so the
user can still inspect or recover it; and refresh the policy when projects are
added or removed. Focused tests cover managed-root denial, restored-root access,
outside-root compatibility, and sibling-prefix containment.
