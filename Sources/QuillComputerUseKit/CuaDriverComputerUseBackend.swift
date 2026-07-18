import Foundation
#if canImport(CoreGraphics) && canImport(ImageIO)
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
#endif

/// Maps QuillCode's `ComputerUseBackend` seam onto the cua-driver tool contract.
///
/// The value of routing through cua-driver instead of the native CGEvent backend is that cua drives
/// apps in the *background*: it does not steal keyboard focus or move the user's real cursor, which is
/// exactly what the unattended-coworker use case needs. The agent-facing tools and the Approved-Apps
/// safety gate are untouched — only the executing driver differs.
///
/// ## Coordinate contract
/// `ComputerUseToolExecutor` performs no coordinate scaling: whatever `screenshot()` reports as
/// `width`/`height` *is* the pixel space the model clicks in, and `leftClick`/`moveCursor` receive
/// coordinates in that same space. cua guarantees this internally — `get_desktop_state`'s screenshot
/// pixels and `click{scope:desktop}`'s `x`/`y` are the same coordinate system. When we downscale the
/// screenshot to keep the artifact small, we report the *downscaled* dimensions to the model and scale
/// the model's coordinates back up to cua's native pixel space before dispatching. That keeps the loop
/// exact: the model always clicks in the space of the image it was handed.
///
/// This is an `actor` because it holds two pieces of mutable state that must stay consistent across
/// calls: the last screenshot's coordinate scale (so a subsequent click lands correctly) and whether
/// the one-time `capture_scope=desktop` config — which also unlocks windowless desktop clicks — has
/// been applied.
public actor CuaDriverComputerUseBackend: ComputerUseBackend, ComputerUseForegroundApplicationProviding {
    public nonisolated let status: ComputerUseStatus

    private let client: any CuaDriverToolInvoking
    private let sessionID: String
    /// Longest edge (in cua native pixels) above which the screenshot is downscaled before it reaches
    /// the model. `nil` disables downscaling (coordinates map 1:1). The default keeps a Retina desktop
    /// capture — often 6000+px wide — down to a size a vision model ingests cheaply.
    private let maxScreenshotDimension: Int?
    private let downscaler: @Sendable (Data, Int) -> CuaScreenshotDownscaler.Output

    private var didApplyDesktopScope = false
    /// Multiply an incoming model coordinate by these to reach cua's native pixel space. Stored per
    /// axis (not one scalar) so a downscaler that doesn't preserve aspect ratio — or the ±1px rounding
    /// difference between an independently-rounded width and height — can't skew the Y axis. Updated on
    /// every `screenshot()`; defaults to 1.0 so a click before any screenshot is passed through as-is.
    private var coordinateScaleX: Double = 1.0
    private var coordinateScaleY: Double = 1.0

    public init(
        client: any CuaDriverToolInvoking,
        status: ComputerUseStatus,
        sessionID: String = "quillcode",
        maxScreenshotDimension: Int? = 1568,
        downscaler: @escaping @Sendable (Data, Int) -> CuaScreenshotDownscaler.Output = CuaScreenshotDownscaler.downscalePNG
    ) {
        self.client = client
        self.status = status
        self.sessionID = sessionID
        self.maxScreenshotDimension = maxScreenshotDimension
        self.downscaler = downscaler
    }

    // MARK: - ComputerUseBackend

    public func screenshot() async throws -> ComputerScreenshot {
        try await ensureDesktopScope()
        // Empty/`session`-only args make get_desktop_state return the native-resolution PNG as base64
        // (its default). The schema is strict (additionalProperties:false), so only `session` is sent.
        let result = try await call("get_desktop_state", ["session": sessionID])
        guard
            let object = CuaJSON.object(from: result),
            let base64 = object["screenshot_png_b64"] as? String,
            let nativeWidth = intValue(object["screenshot_width"]),
            let nativeHeight = intValue(object["screenshot_height"])
        else {
            throw CuaDriverError.malformedResult(
                tool: "get_desktop_state",
                detail: "missing screenshot_png_b64/screenshot_width/screenshot_height"
            )
        }
        guard let pngData = Data(base64Encoded: base64) else {
            throw CuaDriverError.malformedResult(tool: "get_desktop_state", detail: "screenshot_png_b64 not valid base64")
        }

        guard let maxScreenshotDimension, max(nativeWidth, nativeHeight) > maxScreenshotDimension else {
            coordinateScaleX = 1.0
            coordinateScaleY = 1.0
            return ComputerScreenshot(width: nativeWidth, height: nativeHeight, pngBase64: base64)
        }

        let scaled = downscaler(pngData, maxScreenshotDimension)
        // Downscale failed (or produced a degenerate size): report native full-res and keep scale 1.0
        // rather than mis-scaling every coordinate against a zero/garbage width.
        guard scaled.width > 0, scaled.height > 0 else {
            coordinateScaleX = 1.0
            coordinateScaleY = 1.0
            return ComputerScreenshot(width: nativeWidth, height: nativeHeight, pngBase64: base64)
        }
        // Scale each axis from model space (downscaled) back up to cua's native pixel space.
        coordinateScaleX = Double(nativeWidth) / Double(scaled.width)
        coordinateScaleY = Double(nativeHeight) / Double(scaled.height)
        return ComputerScreenshot(
            width: scaled.width,
            height: scaled.height,
            pngBase64: scaled.pngData.base64EncodedString()
        )
    }

    public func leftClick(x: Int, y: Int) async throws {
        // KNOWN LIMITATION (increment 2): a desktop-scope click actuates whatever window is at the
        // absolute coordinate WITHOUT raising it, so it can drive a background window while the
        // Approved-Apps gate (which only inspects the frontmost app) approves a different one. This is
        // the safety cost of background actuation; under the native CGEvent backend a click raises the
        // target, so the gate catches it on the next action. Gating cua by default is blocked on
        // hit-testing the click coordinate to its owning app. Only affects users who configured a
        // restrictive approval policy (default is unrestricted). See docs/CUA_COMPUTER_USE_TEST_PLAN.md.
        try await ensureDesktopScope()
        let native = toNativeCoordinate(x: x, y: y)
        _ = try await call("click", [
            "scope": "desktop",
            "button": "left",
            "x": native.x,
            "y": native.y,
        ])
    }

    public func type(_ text: String) async throws {
        let pid = try await frontmostProcessID()
        _ = try await call("type_text", ["pid": pid, "text": text])
    }

    public func scroll(dx: Int, dy: Int) async throws {
        let pid = try await frontmostProcessID()
        // cua scrolls in line/page units; the contract's dx/dy are pixel deltas, so quantize to lines.
        for step in CuaScrollMapper.steps(dx: dx, dy: dy) {
            _ = try await call("scroll", [
                "pid": pid,
                "direction": step.direction,
                "amount": step.amount,
                "by": "line",
            ])
        }
    }

    public func moveCursor(x: Int, y: Int) async throws {
        // Moves cua's *agent* cursor overlay (not the user's real pointer), scoped to our session so
        // the overlay is attributable and can be cleared. Coordinates are in native pixel space.
        let native = toNativeCoordinate(x: x, y: y)
        _ = try await call("move_cursor", [
            "x": native.x,
            "y": native.y,
            "session": sessionID,
        ])
    }

    public func pressKey(_ key: String) async throws {
        let pid = try await frontmostProcessID()
        let mapped = CuaKeyMapper.map(key)
        _ = try await call("press_key", ["pid": pid, "key": mapped])
    }

    // MARK: - ComputerUseForegroundApplicationProviding

    public func foregroundApplication() async -> ComputerUseApplication? {
        guard let app = try? await frontmostApp() else { return nil }
        return ComputerUseApplication(
            name: app["name"] as? String,
            bundleIdentifier: app["bundle_id"] as? String
        )
    }

    // MARK: - Internals

    private func ensureDesktopScope() async throws {
        guard !didApplyDesktopScope else { return }
        _ = try await call("set_config", ["capture_scope": "desktop"])
        didApplyDesktopScope = true
    }

    private func toNativeCoordinate(x: Int, y: Int) -> (x: Int, y: Int) {
        guard coordinateScaleX != 1.0 || coordinateScaleY != 1.0 else { return (x, y) }
        return (
            Int((Double(x) * coordinateScaleX).rounded()),
            Int((Double(y) * coordinateScaleY).rounded())
        )
    }

    private func frontmostProcessID() async throws -> Int {
        guard let app = try await frontmostApp(), let pid = intValue(app["pid"]) else {
            throw CuaDriverError.toolFailed(tool: "list_apps", message: "no active/frontmost application to target")
        }
        return pid
    }

    /// The frontmost app, or nil if none is marked active. Deliberately does NOT fall back to an
    /// arbitrary first-listed app: input actions resolve their pid through here, and
    /// `foregroundApplication()` feeds the Approved-Apps gate — targeting or approving the *wrong* app
    /// would be worse than failing closed (and matches `MacComputerUseBackend`, which returns nil).
    private func frontmostApp() async throws -> [String: Any]? {
        let result = try await call("list_apps", [:])
        guard let object = CuaJSON.object(from: result), let apps = object["apps"] as? [Any] else {
            return nil
        }
        return apps
            .compactMap { $0 as? [String: Any] }
            .first { boolValue($0["active"]) == true }
    }

    /// Runs a cua tool and surfaces an explicit driver-reported failure. cua returns
    /// `effect: "unverifiable"` for input events it cannot self-confirm (a keystroke), which is NOT a
    /// failure and stays `ok`; but an `error` field or `effect: "failed"` in a 0-exit result means the
    /// action was rejected, and the executor must see that rather than report a false success.
    @discardableResult
    private func call(_ tool: String, _ arguments: [String: Any]) async throws -> Data {
        let result = try await client.callTool(name: tool, argumentsJSON: CuaJSON.encode(arguments))
        if let object = CuaJSON.object(from: result) {
            if let error = object["error"] as? String, !error.isEmpty {
                throw CuaDriverError.toolFailed(tool: tool, message: String(error.prefix(400)))
            }
            if (object["effect"] as? String) == "failed" {
                let detail = (object["message"] as? String) ?? "driver reported effect=failed"
                throw CuaDriverError.toolFailed(tool: tool, message: String(detail.prefix(400)))
            }
        }
        return result
    }

    /// Non-trapping numeric coercion. `Int(exactly:)` on the bridged `Double` avoids a fatal error if a
    /// buggy/hostile driver emits a non-finite or out-of-range number (e.g. `1e400` → `+inf`).
    private nonisolated func intValue(_ value: Any?) -> Int? {
        switch value {
        case let int as Int: return int
        // `Int(exactly:)` returns nil (never traps) for non-finite or out-of-range values.
        case let number as NSNumber: return Int(exactly: number.doubleValue.rounded())
        case let double as Double: return Int(exactly: double.rounded())
        case let string as String: return Int(string)
        default: return nil
        }
    }

    /// Tolerant boolean coercion, mirroring `intValue`'s tolerance: accepts JSON bool, 0/1, and
    /// "true"/"false" so a driver that reports flags as numbers or strings doesn't silently disable
    /// features (grants → permanently `.unavailable`; `active` → wrong-app targeting).
    private nonisolated func boolValue(_ value: Any?) -> Bool? {
        switch value {
        case let bool as Bool: return bool
        case let number as NSNumber: return number.boolValue
        case let string as String:
            switch string.lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: return nil
            }
        default: return nil
        }
    }
}

/// Pure quantization of a pixel scroll delta into cua's line-based scroll steps. Extracted so the
/// mapping is unit-testable without a driver. Roughly 40px == one line, matching a typical wheel notch.
enum CuaScrollMapper {
    struct Step: Equatable {
        var direction: String
        var amount: Int
    }

    static func steps(dx: Int, dy: Int, pixelsPerLine: Int = 40) -> [Step] {
        var steps: [Step] = []
        if dy != 0 {
            steps.append(Step(direction: dy > 0 ? "up" : "down", amount: lines(dy, pixelsPerLine)))
        }
        if dx != 0 {
            steps.append(Step(direction: dx > 0 ? "right" : "left", amount: lines(dx, pixelsPerLine)))
        }
        return steps
    }

    private static func lines(_ delta: Int, _ pixelsPerLine: Int) -> Int {
        max(1, Int((Double(abs(delta)) / Double(pixelsPerLine)).rounded()))
    }
}

/// Normalizes QuillCode's key names onto the tokens cua's `press_key` expects. Pass-through for
/// single printable characters; synonyms folded for the common navigation keys.
enum CuaKeyMapper {
    static func map(_ key: String) -> String {
        let lowered = key.trimmingCharacters(in: .whitespaces).lowercased()
        // Tokens cua's press_key accepts: return, tab, escape, up/down/left/right, space, delete,
        // home, end, pageup, pagedown, f1-f12, plus any single letter/digit.
        switch lowered {
        case "enter": return "return"
        case "esc": return "escape"
        case "backspace", "del": return "delete"
        case "arrowup": return "up"
        case "arrowdown": return "down"
        case "arrowleft": return "left"
        case "arrowright": return "right"
        case "page_up", "pgup": return "pageup"
        case "page_down", "pgdn": return "pagedown"
        default: return lowered.isEmpty ? key : lowered
        }
    }
}

/// Coordinate-safe PNG downscaler. Decodes the PNG, redraws it so its longest edge is at most
/// `maxDimension`, and re-encodes PNG. On any platform without ImageIO, or on decode failure, returns
/// the original bytes and dimensions unchanged (scale 1.0), so the backend degrades to full-res rather
/// than mis-scaling coordinates.
public enum CuaScreenshotDownscaler {
    public struct Output: Sendable {
        public var pngData: Data
        public var width: Int
        public var height: Int
        public init(pngData: Data, width: Int, height: Int) {
            self.pngData = pngData
            self.width = width
            self.height = height
        }
    }

    public static let downscalePNG: @Sendable (Data, Int) -> Output = { data, maxDimension in
        #if canImport(CoreGraphics) && canImport(ImageIO)
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return passthrough(data)
        }
        let width = image.width
        let height = image.height
        let longest = max(width, height)
        guard longest > maxDimension, longest > 0 else {
            return Output(pngData: data, width: width, height: height)
        }
        let scale = Double(maxDimension) / Double(longest)
        let newWidth = max(1, Int((Double(width) * scale).rounded()))
        let newHeight = max(1, Int((Double(height) * scale).rounded()))
        guard
            let context = CGContext(
                data: nil,
                width: newWidth,
                height: newHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return passthrough(data)
        }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        guard
            let scaled = context.makeImage(),
            let encoded = encodePNG(scaled)
        else {
            return passthrough(data)
        }
        return Output(pngData: encoded, width: newWidth, height: newHeight)
        #else
        return passthrough(data)
        #endif
    }

    #if canImport(CoreGraphics) && canImport(ImageIO)
    private static func encodePNG(_ image: CGImage) -> Data? {
        let mutableData = NSMutableData()
        let type = UTType.png.identifier as CFString
        guard let destination = CGImageDestinationCreateWithData(mutableData, type, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutableData as Data
    }
    #endif

    private static func passthrough(_ data: Data) -> Output {
        // Dimensions unknown on failure; report 0 so the caller keeps scale 1.0 and reports native size.
        Output(pngData: data, width: 0, height: 0)
    }
}
