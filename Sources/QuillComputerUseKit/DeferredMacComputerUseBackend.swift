#if canImport(AppKit) && canImport(ApplicationServices) && canImport(CoreGraphics)
import Foundation

final class DeferredMacComputerUseBackend: @unchecked Sendable,
    ComputerUseBackend,
    ComputerUsePermissionRequesting,
    ComputerUseForegroundApplicationProviding,
    ComputerUseApplicationActivating,
    ComputerUseAccessibilitySnapshotProviding,
    WorkflowRecordingBackend
{
    private let lock = NSLock()
    private let makeBackend: @Sendable () -> MacComputerUseBackend
    private var storedBackend: MacComputerUseBackend?

    init(
        makeBackend: @escaping @Sendable () -> MacComputerUseBackend = MacComputerUseBackend.init
    ) {
        self.makeBackend = makeBackend
    }

    var status: ComputerUseStatus {
        backend().status
    }

    func requestScreenRecordingAccess() -> Bool {
        backend().requestScreenRecordingAccess()
    }

    func requestAccessibilityAccess() -> Bool {
        backend().requestAccessibilityAccess()
    }

    func screenshot() async throws -> ComputerScreenshot {
        try await backend().screenshot()
    }

    func leftClick(x: Int, y: Int) async throws {
        try await backend().leftClick(x: x, y: y)
    }

    func type(_ text: String) async throws {
        try await backend().type(text)
    }

    func scroll(dx: Int, dy: Int) async throws {
        try await backend().scroll(dx: dx, dy: dy)
    }

    func moveCursor(x: Int, y: Int) async throws {
        try await backend().moveCursor(x: x, y: y)
    }

    func pressKey(_ key: String) async throws {
        try await backend().pressKey(key)
    }

    func foregroundApplication() async -> ComputerUseApplication? {
        await backend().foregroundApplication()
    }

    func application(matching nameOrBundleIdentifier: String) async -> ComputerUseApplication? {
        await backend().application(matching: nameOrBundleIdentifier)
    }

    func activateApplication(
        matching nameOrBundleIdentifier: String
    ) async throws -> ComputerUseApplication {
        try await backend().activateApplication(matching: nameOrBundleIdentifier)
    }

    func accessibilitySnapshot(limit: Int) async -> ComputerUseAccessibilitySnapshot? {
        await backend().accessibilitySnapshot(limit: limit)
    }

    func workflowRecordingStatus() async -> WorkflowRecordingStatus {
        guard let backend = backendIfMaterialized() else { return .idle }
        return await backend.workflowRecordingStatus()
    }

    var workflowRecordingStatusSnapshot: WorkflowRecordingStatus {
        backendIfMaterialized()?.workflowRecordingStatusSnapshot ?? .idle
    }

    func startWorkflowRecording(
        _ request: WorkflowRecordingRequest
    ) async throws -> WorkflowRecordingStatus {
        try await backend().startWorkflowRecording(request)
    }

    func stopWorkflowRecording() async throws -> WorkflowRecordingCapture {
        try await backend().stopWorkflowRecording()
    }

    func cancelWorkflowRecording() async {
        guard let backend = backendIfMaterialized() else { return }
        await backend.cancelWorkflowRecording()
    }

    private func backend() -> MacComputerUseBackend {
        lock.withLock {
            if let storedBackend {
                return storedBackend
            }
            let backend = makeBackend()
            storedBackend = backend
            return backend
        }
    }

    private func backendIfMaterialized() -> MacComputerUseBackend? {
        lock.withLock { storedBackend }
    }
}
#endif
