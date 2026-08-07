import Darwin
import Foundation

enum QuillCodeDesktopLaunchClock {
    static let appEntryUptime = ProcessInfo.processInfo.systemUptime
}

struct QuillCodeDesktopPerformanceSnapshot: Equatable, Sendable {
    static let schemaVersion = 1
    static let measurement = "initial-live-window"

    var launchReadyMilliseconds: Double
    var residentMemoryBytes: Int64
    var threadCount: Int

    static func capture(
        launchStartedAtUptime: TimeInterval,
        nowUptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) throws -> Self {
        var taskInfo = proc_taskinfo()
        let expectedSize = Int32(MemoryLayout<proc_taskinfo>.stride)
        let capturedSize = withUnsafeMutablePointer(to: &taskInfo) { pointer in
            proc_pidinfo(
                getpid(),
                PROC_PIDTASKINFO,
                0,
                pointer,
                expectedSize
            )
        }
        guard capturedSize == expectedSize,
              taskInfo.pti_resident_size > 0,
              taskInfo.pti_threadnum > 0
        else {
            throw QuillCodeDesktopSmokeFailure.performanceSnapshotUnavailable
        }

        let elapsed = nowUptime - launchStartedAtUptime
        guard elapsed.isFinite, elapsed >= 0 else {
            throw QuillCodeDesktopSmokeFailure.performanceSnapshotUnavailable
        }
        let milliseconds = (elapsed * 100_000).rounded() / 100

        return Self(
            launchReadyMilliseconds: milliseconds,
            residentMemoryBytes: clampedInt64(taskInfo.pti_resident_size),
            threadCount: Int(taskInfo.pti_threadnum)
        )
    }

    var dictionary: [String: Any] {
        [
            "schemaVersion": Self.schemaVersion,
            "measurement": Self.measurement,
            "launchReadyMilliseconds": launchReadyMilliseconds,
            "residentMemoryBytes": residentMemoryBytes,
            "threadCount": threadCount
        ]
    }

    private static func clampedInt64(_ value: UInt64) -> Int64 {
        Int64(min(value, UInt64(Int64.max)))
    }
}
