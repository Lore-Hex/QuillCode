import XCTest
#if canImport(CoreGraphics) && canImport(ImageIO)
import CoreGraphics
import ImageIO
#endif
@testable import QuillComputerUseKit

/// Live drive against a real cua-driver binary. Skipped unless `QUILLCODE_CUA_LIVE_BINARY` points at
/// an installed driver, so CI (which has no binary) stays green while a developer can prove the whole
/// read path — get_desktop_state → base64 → coordinate-safe downscale → reported dims — works
/// end-to-end through the production Swift types, not a fake. Read-only: no clicks or typing.
final class CuaDriverLiveDriveTests: XCTestCase {
    private func liveBinaryPath() throws -> String {
        guard let path = ProcessInfo.processInfo.environment["QUILLCODE_CUA_LIVE_BINARY"],
              FileManager.default.isExecutableFile(atPath: path) else {
            throw XCTSkip("Set QUILLCODE_CUA_LIVE_BINARY=/path/to/cua-driver to run the live drive.")
        }
        return path
    }

    func testLocatorProbesRealDriverStatus() async throws {
        let path = try liveBinaryPath()
        let backend = await CuaDriverLocator().makeBackendIfAvailable(explicitPath: path)
        let resolved = try XCTUnwrap(backend, "locator must build a backend for a real binary")
        // Grants reflect the *caller's* (this test process's) TCC identity — may or may not be granted
        // in a given environment, so we only assert the status was populated coherently.
        XCTAssertEqual(resolved.status.available,
                       resolved.status.screenRecordingGranted && resolved.status.accessibilityGranted)
    }

    func testScreenshotIsDownscaledAndDecodesToReportedDimensions() async throws {
        let path = try liveBinaryPath()
        let client = CuaDriverProcessClient(driverPath: path)
        let backend = CuaDriverComputerUseBackend(
            client: client,
            status: .permissionStatus(screenRecordingGranted: true, accessibilityGranted: true),
            maxScreenshotDimension: 1568
        )

        let shot = try await backend.screenshot()

        XCTAssertLessThanOrEqual(max(shot.width, shot.height), 1568,
                                 "screenshot must be downscaled to the configured cap")
        let data = try XCTUnwrap(Data(base64Encoded: shot.pngBase64), "pngBase64 must decode")
        XCTAssertGreaterThan(data.count, 0)

        #if canImport(CoreGraphics) && canImport(ImageIO)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, shot.width, "reported width must match the actual PNG the model sees")
        XCTAssertEqual(image.height, shot.height, "reported height must match the actual PNG")
        #endif
    }

    func testForegroundApplicationResolvesRealApp() async throws {
        let path = try liveBinaryPath()
        let client = CuaDriverProcessClient(driverPath: path)
        let backend = CuaDriverComputerUseBackend(
            client: client,
            status: .permissionStatus(screenRecordingGranted: true, accessibilityGranted: true)
        )
        let app = await backend.foregroundApplication()
        XCTAssertNotNil(app?.displayLabel, "a frontmost app should always resolve on a live desktop")
    }
}
