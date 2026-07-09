public actor StubComputerUseBackend: ComputerUseBackend,
    ComputerUseForegroundApplicationProviding,
    ComputerUseAccessibilitySnapshotProviding
{
    public private(set) var actions: [String] = []
    private let application: ComputerUseApplication?
    private let snapshot: ComputerUseAccessibilitySnapshot?

    public nonisolated var status: ComputerUseStatus {
        .permissionStatus(
            screenRecordingGranted: true,
            accessibilityGranted: true
        )
    }

    public init(
        foregroundApplication: ComputerUseApplication? = nil,
        accessibilitySnapshot: ComputerUseAccessibilitySnapshot? = nil
    ) {
        self.application = foregroundApplication
        self.snapshot = accessibilitySnapshot
    }

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

    public func foregroundApplication() async -> ComputerUseApplication? {
        application
    }

    public func accessibilitySnapshot(limit: Int) async -> ComputerUseAccessibilitySnapshot? {
        guard let snapshot else { return nil }
        return ComputerUseAccessibilitySnapshot(elements: Array(snapshot.elements.prefix(max(0, limit))))
    }
}
