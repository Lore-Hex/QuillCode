public actor StubComputerUseBackend: ComputerUseBackend {
    public private(set) var actions: [String] = []

    public nonisolated var status: ComputerUseStatus {
        .permissionStatus(
            screenRecordingGranted: true,
            accessibilityGranted: true
        )
    }

    public init() {}

    public func recordedActions() -> [String] {
        actions
    }

    public func screenshot() async throws -> ComputerScreenshot {
        actions.append("screenshot")
        return ComputerScreenshot(width: 1, height: 1, pngBase64: "iVBORw0KGgo=")
    }

    public func leftClick(x: Int, y: Int) async throws {
        actions.append("leftClick:\(x),\(y)")
    }

    public func type(_ text: String) async throws {
        actions.append("type:\(text)")
    }

    public func scroll(dx: Int, dy: Int) async throws {
        actions.append("scroll:\(dx),\(dy)")
    }

    public func moveCursor(x: Int, y: Int) async throws {
        actions.append("move:\(x),\(y)")
    }

    public func pressKey(_ key: String) async throws {
        actions.append("key:\(key)")
    }
}
