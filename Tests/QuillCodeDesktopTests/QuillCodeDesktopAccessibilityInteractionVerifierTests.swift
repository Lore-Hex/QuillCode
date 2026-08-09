import CoreGraphics
import XCTest
@testable import quill_code_desktop

@MainActor
final class QuillCodeDesktopAccessibilityInteractionVerifierTests: XCTestCase {
    func testStableFrameSamplerRetriesMissingAndChangingFrames() async {
        let frames: [CGRect?] = [
            nil,
            CGRect(x: 10, y: 20, width: 620, height: 80),
            CGRect(x: 10, y: 20, width: 600, height: 80),
            CGRect(x: 10.2, y: 20, width: 600.2, height: 80),
            CGRect(x: 10, y: 20, width: 600, height: 80)
        ]
        var sampleIndex = 0

        let result = await QuillCodeDesktopAccessibilityLayoutSampler.waitForStableFrame(
            maximumAttempts: frames.count,
            requiredStableSamples: 3,
            retryIntervalNanoseconds: 0
        ) {
            defer { sampleIndex += 1 }
            return frames[sampleIndex]
        }

        XCTAssertEqual(result?.width, 600)
        XCTAssertEqual(sampleIndex, frames.count)
    }

    func testStableFrameSamplerIgnoresStaleFramesUntilMinimumWidthIsRestored() async {
        let frames = [
            CGRect(x: 10, y: 20, width: 500, height: 80),
            CGRect(x: 10, y: 20, width: 500, height: 80),
            CGRect(x: 10, y: 20, width: 500, height: 80),
            CGRect(x: 10, y: 20, width: 760, height: 80),
            CGRect(x: 10, y: 20, width: 760, height: 80),
            CGRect(x: 10, y: 20, width: 760, height: 80)
        ]
        var sampleIndex = 0

        let result = await QuillCodeDesktopAccessibilityLayoutSampler.waitForStableFrame(
            maximumAttempts: frames.count,
            requiredStableSamples: 3,
            retryIntervalNanoseconds: 0,
            accepts: { $0.width >= 740 }
        ) {
            defer { sampleIndex += 1 }
            return frames[sampleIndex]
        }

        XCTAssertEqual(result?.width, 760)
        XCTAssertEqual(sampleIndex, frames.count)
    }

    func testStableFrameSamplerFailsAtBoundWhenMeasurementsDoNotStabilize() async {
        let frames: [CGRect?] = [
            CGRect(x: 10, y: 20, width: 600, height: 80),
            nil,
            CGRect(x: 10, y: 20, width: 600, height: 80),
            CGRect(x: 10, y: 20, width: 620, height: 80)
        ]
        var sampleIndex = 0

        let result = await QuillCodeDesktopAccessibilityLayoutSampler.waitForStableFrame(
            maximumAttempts: frames.count,
            requiredStableSamples: 2,
            retryIntervalNanoseconds: 0
        ) {
            defer { sampleIndex += 1 }
            return frames[sampleIndex]
        }

        XCTAssertNil(result)
        XCTAssertEqual(sampleIndex, frames.count)
    }
}
