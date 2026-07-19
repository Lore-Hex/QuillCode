# cua-driver Computer-Use Backend — Test Plan

Adopts TryCua's [`cua-driver`](https://github.com/trycua/cua) (MIT) behind QuillCode's existing
`ComputerUseBackend` seam so computer use can run in the **background** — without stealing keyboard
focus or moving the user's real cursor — which is the property the unattended-coworker use case needs.
The agent-facing tools and the Approved-Apps safety gate are unchanged; only the executing driver
differs.

## Architecture (increment 1)

| Piece | File | Role |
|---|---|---|
| Transport protocol | `CuaDriverClient.swift` (`CuaDriverToolInvoking`) | one-tool-call abstraction, fake-able |
| Production transport | `CuaDriverProcessClient.swift` | shells `cua-driver call <tool> <json>` (in-process, inherits caller TCC) |
| Backend | `CuaDriverComputerUseBackend.swift` | maps the 6 `ComputerUseBackend` methods + foreground app onto cua tools |
| Locator | `CuaDriverLocator.swift` | binary discovery, telemetry-off, `check_permissions` → status |
| Selection | `ComputerUseBackendFactory.cuaDriverPreferred` + desktop coordinator | env-gated opt-in swap |

**Opt-in:** off by default. Set `QUILLCODE_USE_CUA_DRIVER=1` (and optionally
`QUILLCODE_CUA_DRIVER_PATH=/path/to/cua-driver`) to route through cua. Existing installs are untouched.
A Settings toggle backed by config is increment 2.

## Coordinate contract (the load-bearing correctness property)

`ComputerUseToolExecutor` does **no** coordinate scaling: the dimensions `screenshot()` reports *are*
the pixel space the model clicks in, and `leftClick`/`moveCursor` receive coordinates in that same
space. cua guarantees this internally — `get_desktop_state` screenshot pixels ↔ `click{scope:desktop}`
x/y are the same system. Because a Retina desktop capture is huge (6016×3384 here), the backend
downscales the PNG to `maxScreenshotDimension` (default 1568), reports the **downscaled** dims to the
model, and scales the model's coordinates **back up** to cua's native pixel space before dispatch —
so the loop stays exact. On any downscale failure it reports native full-res with scale 1.0 rather
than mis-scaling.

## Automated tests

- **Unit** (`swift test --filter QuillComputerUseKitTests`, no subprocess):
  `CuaDriverComputerUseBackendTests` (screenshot parse + downscale coordinate scale + set_config-once
  + type/scroll/move/key/click mapping + frontmost pid resolution + malformed/no-app errors),
  `CuaDriverLocatorTests` (path resolution precedence + tilde + status parse + scripted telemetry &
  permission probe), `CuaDriverProcessClientTests` (non-zero exit → `toolFailed`).
- **Live drive** (`CuaDriverLiveDriveTests`, gated on `QUILLCODE_CUA_LIVE_BINARY`): drives the real
  driver through the **production Swift types** — screenshot is downscaled to ≤1568 and the reported
  dims exactly match the decoded PNG; foreground app + locator status resolve against a real desktop.
- **Smoke** (`scripts/cua-driver-smoke.sh`): driver-level read path (permissions, desktop scope,
  native PNG capture, frontmost resolution) + the gated Swift live test. Fires **no** input events.

## What is proven live vs. needs packaged-app QA

Verified live against cua-driver 0.8.3 (this machine, sandboxed terminal):

- ✅ **Screenshot read path** end-to-end through the Swift types (6016×3384 → ≤1568, dims match PNG).
- ✅ **Foreground-app resolution**, **locator status probe**, **telemetry-off**.
- ✅ **No-focus-steal**: a background `type_text` into a backgrounded TextEdit left Firefox frontmost.
- ✅ Every action mapping emits the correct cua tool call, and cua **accepts** each without error
  (`effect: "unverifiable"` = the event was posted; the driver simply can't self-verify a keystroke).

Needs verification in the **packaged QuillCode app** (holds Accessibility for the native backend):

- ⚠️ **AX-dependent write landing** (`type_text` via `AXSetAttribute(kAXSelectedText)`, `get_window_state`,
  `set_value`). Under a sandboxed terminal's TCC identity the per-app AX tree walk returned empty
  (`window_id: None, elements: 0`) even though `check_permissions` reported Accessibility granted, so a
  keystroke could not be confirmed landing. In the packaged app the `call` path attributes AX to
  QuillCode's own grant, which should resolve this. **This is the top manual-QA item**, and it is the
  strongest argument for increment 2 (persistent `mcp --embedded`, which explicitly *inherits the
  host's TCC grants* and also enables the agent-cursor overlay).

### Manual QA checklist (packaged app)

1. Grant QuillCode Screen Recording + Accessibility (existing native-backend setup).
2. Launch with `QUILLCODE_USE_CUA_DRIVER=1`; confirm Settings → Computer Use shows "ready" (cua status).
3. Ask the agent to screenshot; confirm the artifact is a real screen capture at ≤1568px.
4. Ask the agent to click a visible control by coordinates read off the screenshot; confirm the click
   lands on the right control (coordinate contract) **and the user's real cursor does not move**.
5. Ask the agent to type into a focused text field; confirm the text lands (closes the AX-write item).
6. Confirm that a pure screenshot does **not** raise/front the observed app (background read).

## Known safety limitation (increment-2 blocker for default-on)

**Background desktop-click can bypass the Approved-Apps gate.** The gate identifies the app to approve
via the *frontmost* app (`foregroundApplication()`), but `leftClick` issues a `click{scope:desktop,x,y}`
that actuates whatever window sits at that absolute coordinate **without raising it**. So a click can
drive a control in a background, unapproved app while the gate approved the frontmost one. Under the
native CGEvent backend this is mitigated because a click raises the target app (the gate then catches
it on the next action); cua's background click removes that mitigation. This only affects users who
configured a restrictive `ComputerUseAppApprovalPolicy` (the default is `.unrestricted`), and cua is
itself opt-in — but **gating cua on by default is blocked** on hit-testing the click coordinate to its
owning app (cua exposes `get_accessibility_tree`/`list_windows` bounds for this) so the gate evaluates
the app actually being actuated. Tracked as the top increment-2 safety item.

Adjacent honesty note: cua returns `effect:"unverifiable"` for input events it cannot self-confirm
(a keystroke). The backend surfaces an *explicit* driver failure (`error` field / `effect:"failed"`)
as a thrown error, but an unverifiable-yet-didn't-land keystroke (the AX-focus case above) cannot be
detected by cua and will read as success — another reason the AX-write path needs packaged-app QA.

## Increment roadmap

1. **(this)** one-shot `call` transport behind the seam; env-gated; read path proven live.
2. Persistent `mcp --embedded` transport: host-grant inheritance (fixes AX-write identity) +
   agent-cursor overlay + lower per-action latency (no per-call process spawn).
3. `lume` micro-VM sandbox for fully-isolated computer use.
