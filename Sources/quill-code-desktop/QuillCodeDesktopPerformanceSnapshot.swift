import Darwin
import Foundation

enum QuillCodeDesktopLaunchClock {
    static let appEntryUptime = ProcessInfo.processInfo.systemUptime
}

struct QuillCodeDesktopProcessResourceSnapshot: Equatable, Sendable {
    var residentMemoryBytes: Int64
    var threadCount: Int

    static func capture() throws -> Self {
        var virtualMemoryInfo = task_vm_info_data_t()
        var virtualMemoryInfoCount = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let virtualMemoryResult = withUnsafeMutablePointer(to: &virtualMemoryInfo) { pointer in
            pointer.withMemoryRebound(
                to: integer_t.self,
                capacity: Int(virtualMemoryInfoCount)
            ) { reboundPointer in
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_VM_INFO),
                    reboundPointer,
                    &virtualMemoryInfoCount
                )
            }
        }

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
        guard virtualMemoryResult == KERN_SUCCESS,
              virtualMemoryInfo.phys_footprint > 0,
              capturedSize == expectedSize,
              taskInfo.pti_threadnum > 0
        else {
            throw QuillCodeDesktopSmokeFailure.performanceSnapshotUnavailable
        }
        return Self(
            residentMemoryBytes: Int64(
                min(virtualMemoryInfo.phys_footprint, UInt64(Int64.max))
            ),
            threadCount: Int(taskInfo.pti_threadnum)
        )
    }
}

struct QuillCodeDesktopInitialPerformanceSnapshot: Equatable, Sendable {
    static let measurement = "initial-live-window"

    var workload: QuillCodeDesktopPerformanceWorkload
    var launchReadyMilliseconds: Double
    var resources: QuillCodeDesktopProcessResourceSnapshot

    static func capture(
        workload: QuillCodeDesktopPerformanceWorkload = .firstRunEmpty,
        launchStartedAtUptime: TimeInterval,
        nowUptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) throws -> Self {
        let elapsed = nowUptime - launchStartedAtUptime
        guard elapsed.isFinite, elapsed >= 0 else {
            throw QuillCodeDesktopSmokeFailure.performanceSnapshotUnavailable
        }
        let milliseconds = (elapsed * 100_000).rounded() / 100

        return Self(
            workload: workload,
            launchReadyMilliseconds: milliseconds,
            resources: try QuillCodeDesktopProcessResourceSnapshot.capture()
        )
    }

    func completingRepeatedInteractionSweep(
        firstSweepResources: QuillCodeDesktopProcessResourceSnapshot
    ) throws -> QuillCodeDesktopPerformanceSnapshot {
        QuillCodeDesktopPerformanceSnapshot(
            workload: workload,
            launchReadyMilliseconds: launchReadyMilliseconds,
            initialResources: resources,
            postInteractionResources: firstSweepResources,
            repeatedInteractionResources: try QuillCodeDesktopProcessResourceSnapshot.capture()
        )
    }
}

struct QuillCodeDesktopPerformanceSnapshot: Equatable, Sendable {
    static let schemaVersion = 5
    static let memoryMeasurement = "physical-footprint"
    static let measurement = QuillCodeDesktopInitialPerformanceSnapshot.measurement
    static let postInteractionMeasurement = "settled-after-native-interaction-sweep"
    static let repeatedInteractionMeasurement = "settled-after-repeated-native-interaction-sweep"
    static let interactionSweepCount = 2

    var workload: QuillCodeDesktopPerformanceWorkload = .firstRunEmpty
    var launchReadyMilliseconds: Double
    var initialResources: QuillCodeDesktopProcessResourceSnapshot
    var postInteractionResources: QuillCodeDesktopProcessResourceSnapshot
    var repeatedInteractionResources: QuillCodeDesktopProcessResourceSnapshot

    var residentMemoryBytes: Int64 { initialResources.residentMemoryBytes }
    var threadCount: Int { initialResources.threadCount }
    var residentMemoryGrowthBytes: Int64 {
        postInteractionResources.residentMemoryBytes - initialResources.residentMemoryBytes
    }
    var threadGrowth: Int {
        postInteractionResources.threadCount - initialResources.threadCount
    }
    var repeatedInteractionResidentMemoryGrowthBytes: Int64 {
        repeatedInteractionResources.residentMemoryBytes - postInteractionResources.residentMemoryBytes
    }
    var repeatedInteractionThreadGrowth: Int {
        repeatedInteractionResources.threadCount - postInteractionResources.threadCount
    }

    var dictionary: [String: Any] {
        [
            "schemaVersion": Self.schemaVersion,
            "workload": workload.rawValue,
            "measurement": Self.measurement,
            "memoryMeasurement": Self.memoryMeasurement,
            "launchReadyMilliseconds": launchReadyMilliseconds,
            "residentMemoryBytes": residentMemoryBytes,
            "threadCount": threadCount,
            "postInteractionMeasurement": Self.postInteractionMeasurement,
            "postInteractionResidentMemoryBytes": postInteractionResources.residentMemoryBytes,
            "postInteractionThreadCount": postInteractionResources.threadCount,
            "residentMemoryGrowthBytes": residentMemoryGrowthBytes,
            "threadGrowth": threadGrowth,
            "repeatedInteractionMeasurement": Self.repeatedInteractionMeasurement,
            "interactionSweepCount": Self.interactionSweepCount,
            "repeatedInteractionResidentMemoryBytes": repeatedInteractionResources.residentMemoryBytes,
            "repeatedInteractionThreadCount": repeatedInteractionResources.threadCount,
            "repeatedInteractionResidentMemoryGrowthBytes": repeatedInteractionResidentMemoryGrowthBytes,
            "repeatedInteractionThreadGrowth": repeatedInteractionThreadGrowth
        ]
    }
}
