import CoreGraphics
import Foundation

@MainActor
enum QuillCodeDesktopAccessibilityLayoutSampler {
    static func waitForStableFrame(
        maximumAttempts: Int = 40,
        requiredStableSamples: Int = 3,
        retryIntervalNanoseconds: UInt64 = 50_000_000,
        accepts: (CGRect) -> Bool = { _ in true },
        sample: () -> CGRect?
    ) async -> CGRect? {
        let attemptCount = max(1, maximumAttempts)
        let stableSampleCount = max(1, requiredStableSamples)
        var previousFrame: CGRect?
        var matchingSampleCount = 0

        for attempt in 0..<attemptCount {
            if let frame = sample(), isMeasurable(frame), accepts(frame) {
                if let previousFrame, framesMatch(previousFrame, frame) {
                    matchingSampleCount += 1
                } else {
                    previousFrame = frame
                    matchingSampleCount = 1
                }
                if matchingSampleCount >= stableSampleCount {
                    return frame
                }
            } else {
                previousFrame = nil
                matchingSampleCount = 0
            }

            guard attempt + 1 < attemptCount, !Task.isCancelled else { break }
            try? await Task.sleep(nanoseconds: retryIntervalNanoseconds)
        }
        return nil
    }

    private static func isMeasurable(_ frame: CGRect) -> Bool {
        frame.origin.x.isFinite
            && frame.origin.y.isFinite
            && frame.width.isFinite
            && frame.height.isFinite
            && frame.width > 0
            && frame.height > 0
    }

    private static func framesMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let tolerance: CGFloat = 0.5
        return abs(lhs.minX - rhs.minX) <= tolerance
            && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance
            && abs(lhs.height - rhs.height) <= tolerance
    }
}
