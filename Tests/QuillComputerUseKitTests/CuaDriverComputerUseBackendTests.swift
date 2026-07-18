import XCTest
@testable import QuillComputerUseKit

/// A scripted `CuaDriverToolInvoking` that records every call and returns canned JSON per tool name,
/// so the whole backend mapping is exercised without a subprocess.
private actor ScriptedCuaDriver: CuaDriverToolInvoking {
    private var calls: [(name: String, argumentsJSON: Data)] = []
    private var responses: [String: Data]

    init(responses: [String: Data] = [:]) {
        self.responses = responses
    }

    func callTool(name: String, argumentsJSON: Data) async throws -> Data {
        calls.append((name, argumentsJSON))
        return responses[name] ?? Data("{}".utf8)
    }

    func callNames() -> [String] { calls.map(\.name) }
    /// Raw arguments JSON for the first call to `name` (Data is Sendable across the actor boundary).
    func firstCallJSON(_ name: String) -> Data? { calls.first { $0.name == name }?.argumentsJSON }
    func count(of name: String) -> Int { calls.filter { $0.name == name }.count }
}

private func json(_ object: [String: Any]) -> Data {
    try! JSONSerialization.data(withJSONObject: object)
}

/// Parses recorded argument JSON in the (nonisolated) test context.
private func args(_ data: Data?) -> [String: Any] {
    guard let data, let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        return [:]
    }
    return object
}

/// list_apps payload with Safari (pid 200) frontmost.
private let listAppsResponse = json([
    "apps": [
        ["active": false, "pid": 100, "name": "Finder", "bundle_id": "com.apple.finder"],
        ["active": true, "pid": 200, "name": "Safari", "bundle_id": "com.apple.Safari"],
    ]
])

final class CuaDriverComputerUseBackendTests: XCTestCase {
    private func makeBackend(
        responses: [String: Data],
        maxScreenshotDimension: Int? = nil,
        downscaler: (@Sendable (Data, Int) -> CuaScreenshotDownscaler.Output)? = nil
    ) -> (CuaDriverComputerUseBackend, ScriptedCuaDriver) {
        let driver = ScriptedCuaDriver(responses: responses)
        let backend = CuaDriverComputerUseBackend(
            client: driver,
            status: .permissionStatus(screenRecordingGranted: true, accessibilityGranted: true),
            sessionID: "quillcode",
            maxScreenshotDimension: maxScreenshotDimension,
            downscaler: downscaler ?? CuaScreenshotDownscaler.downscalePNG
        )
        return (backend, driver)
    }

    // MARK: - Screenshot

    func testScreenshotSetsDesktopScopeOnceAndParsesNativeDimensions() async throws {
        let base64 = Data("hello".utf8).base64EncodedString()
        let (backend, driver) = makeBackend(responses: [
            "get_desktop_state": json([
                "screenshot_png_b64": base64,
                "screenshot_width": 6016,
                "screenshot_height": 3384,
            ]),
        ])

        let shot = try await backend.screenshot()

        XCTAssertEqual(shot.width, 6016)
        XCTAssertEqual(shot.height, 3384)
        XCTAssertEqual(shot.pngBase64, base64)

        let names = await driver.callNames()
        XCTAssertEqual(names, ["set_config", "get_desktop_state"])
        let config = args(await driver.firstCallJSON("set_config"))
        XCTAssertEqual(config["capture_scope"] as? String, "desktop")
        let state = args(await driver.firstCallJSON("get_desktop_state"))
        XCTAssertEqual(state["session"] as? String, "quillcode")
    }

    func testDesktopScopeAppliedOnlyOnceAcrossCalls() async throws {
        let base64 = Data("x".utf8).base64EncodedString()
        let (backend, driver) = makeBackend(responses: [
            "get_desktop_state": json([
                "screenshot_png_b64": base64, "screenshot_width": 10, "screenshot_height": 10,
            ]),
        ])

        _ = try await backend.screenshot()
        try await backend.leftClick(x: 1, y: 1)
        _ = try await backend.screenshot()

        let configCount = await driver.count(of: "set_config")
        XCTAssertEqual(configCount, 1, "capture_scope=desktop must be applied exactly once per backend")
    }

    func testScreenshotDownscaleComputesCoordinateScale() async throws {
        let base64 = Data("bigimage".utf8).base64EncodedString()
        let (backend, driver) = makeBackend(
            responses: [
                "get_desktop_state": json([
                    "screenshot_png_b64": base64, "screenshot_width": 200, "screenshot_height": 100,
                ]),
                "click": json([:]),
            ],
            maxScreenshotDimension: 100,
            downscaler: { _, _ in
                CuaScreenshotDownscaler.Output(pngData: Data("small".utf8), width: 100, height: 50)
            }
        )

        let shot = try await backend.screenshot()
        XCTAssertEqual(shot.width, 100)
        XCTAssertEqual(shot.height, 50)
        XCTAssertEqual(shot.pngBase64, Data("small".utf8).base64EncodedString())

        // Model clicks in downscaled space (100 wide); backend scales back to native (200 wide) => 2x.
        try await backend.leftClick(x: 10, y: 20)
        let click = args(await driver.firstCallJSON("click"))
        XCTAssertEqual(click["x"] as? Int, 20)
        XCTAssertEqual(click["y"] as? Int, 40)
        XCTAssertEqual(click["scope"] as? String, "desktop")
        XCTAssertEqual(click["button"] as? String, "left")
    }

    func testScreenshotDownscaleFailureFallsBackToNativeAndScaleOne() async throws {
        let base64 = Data("bigimage".utf8).base64EncodedString()
        let (backend, driver) = makeBackend(
            responses: [
                "get_desktop_state": json([
                    "screenshot_png_b64": base64, "screenshot_width": 200, "screenshot_height": 100,
                ]),
                "click": json([:]),
            ],
            maxScreenshotDimension: 100,
            downscaler: { data, _ in
                CuaScreenshotDownscaler.Output(pngData: data, width: 0, height: 0) // failure sentinel
            }
        )

        let shot = try await backend.screenshot()
        XCTAssertEqual(shot.width, 200, "must report native size when downscale fails")
        XCTAssertEqual(shot.height, 100)
        XCTAssertEqual(shot.pngBase64, base64)

        try await backend.leftClick(x: 10, y: 20)
        let click = args(await driver.firstCallJSON("click"))
        XCTAssertEqual(click["x"] as? Int, 10, "no coordinate scaling when downscale failed")
        XCTAssertEqual(click["y"] as? Int, 20)
    }

    func testScreenshotMalformedResultThrows() async throws {
        let (backend, _) = makeBackend(responses: [
            "get_desktop_state": json(["screenshot_width": 10]), // missing b64 + height
        ])
        do {
            _ = try await backend.screenshot()
            XCTFail("expected malformedResult")
        } catch let error as CuaDriverError {
            guard case .malformedResult = error else { return XCTFail("wrong error: \(error)") }
        }
    }

    // MARK: - Input actions

    func testTypeResolvesFrontmostPid() async throws {
        let (backend, driver) = makeBackend(responses: [
            "list_apps": listAppsResponse,
            "type_text": json([:]),
        ])
        try await backend.type("hello world")
        let typed = args(await driver.firstCallJSON("type_text"))
        XCTAssertEqual(typed["pid"] as? Int, 200)
        XCTAssertEqual(typed["text"] as? String, "hello world")
    }

    func testScrollQuantizesToLineSteps() async throws {
        let (backend, driver) = makeBackend(responses: [
            "list_apps": listAppsResponse,
            "scroll": json([:]),
        ])
        try await backend.scroll(dx: 0, dy: 80)
        let scroll = args(await driver.firstCallJSON("scroll"))
        XCTAssertEqual(scroll["pid"] as? Int, 200)
        XCTAssertEqual(scroll["direction"] as? String, "up")
        XCTAssertEqual(scroll["amount"] as? Int, 2)
        XCTAssertEqual(scroll["by"] as? String, "line")
    }

    func testMoveCursorTargetsAgentOverlaySession() async throws {
        let (backend, driver) = makeBackend(responses: ["move_cursor": json([:])])
        try await backend.moveCursor(x: 5, y: 6)
        let move = args(await driver.firstCallJSON("move_cursor"))
        XCTAssertEqual(move["x"] as? Int, 5)
        XCTAssertEqual(move["y"] as? Int, 6)
        XCTAssertEqual(move["session"] as? String, "quillcode")
        // move_cursor must NOT need desktop scope (no set_config emitted).
        let names = await driver.callNames()
        XCTAssertFalse(names.contains("set_config"))
    }

    func testPressKeyMapsAndTargetsPid() async throws {
        let (backend, driver) = makeBackend(responses: [
            "list_apps": listAppsResponse,
            "press_key": json([:]),
        ])
        try await backend.pressKey("enter")
        let key = args(await driver.firstCallJSON("press_key"))
        XCTAssertEqual(key["pid"] as? Int, 200)
        XCTAssertEqual(key["key"] as? String, "return")
    }

    func testForegroundApplicationParsesActiveApp() async throws {
        let (backend, _) = makeBackend(responses: ["list_apps": listAppsResponse])
        let app = await backend.foregroundApplication()
        XCTAssertEqual(app?.name, "Safari")
        XCTAssertEqual(app?.bundleIdentifier, "com.apple.Safari")
    }

    func testTypeWithNoActiveAppThrows() async throws {
        let (backend, _) = makeBackend(responses: ["list_apps": json(["apps": []])])
        do {
            try await backend.type("x")
            XCTFail("expected failure when no frontmost app")
        } catch let error as CuaDriverError {
            guard case .toolFailed = error else { return XCTFail("wrong error: \(error)") }
        }
    }

    // MARK: - Pure mappers

    func testScrollMapperSteps() {
        XCTAssertEqual(CuaScrollMapper.steps(dx: 0, dy: 80), [.init(direction: "up", amount: 2)])
        XCTAssertEqual(CuaScrollMapper.steps(dx: 0, dy: -40), [.init(direction: "down", amount: 1)])
        XCTAssertEqual(CuaScrollMapper.steps(dx: 120, dy: 0), [.init(direction: "right", amount: 3)])
        XCTAssertEqual(CuaScrollMapper.steps(dx: -10, dy: 0), [.init(direction: "left", amount: 1)])
        XCTAssertEqual(
            CuaScrollMapper.steps(dx: 40, dy: 40),
            [.init(direction: "up", amount: 1), .init(direction: "right", amount: 1)]
        )
        XCTAssertEqual(CuaScrollMapper.steps(dx: 0, dy: 0), [])
    }

    func testKeyMapper() {
        XCTAssertEqual(CuaKeyMapper.map("enter"), "return")
        XCTAssertEqual(CuaKeyMapper.map("Return"), "return")
        XCTAssertEqual(CuaKeyMapper.map("esc"), "escape")
        XCTAssertEqual(CuaKeyMapper.map("ArrowUp"), "up")
        XCTAssertEqual(CuaKeyMapper.map("backspace"), "delete")
        XCTAssertEqual(CuaKeyMapper.map("pageup"), "pageup")
        XCTAssertEqual(CuaKeyMapper.map("page_up"), "pageup")
        XCTAssertEqual(CuaKeyMapper.map("a"), "a")
        XCTAssertEqual(CuaKeyMapper.map("F5"), "f5")
    }
}
