import Darwin
import Foundation

enum QuillCodeDesktopUpdateProcessMonitor {
    static func waitForExit(_ processID: Int32, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if kill(processID, 0) == -1 && errno == ESRCH { return true }
            usleep(100_000)
        }
        return kill(processID, 0) == -1 && errno == ESRCH
    }

    static func waitForFile(_ url: URL, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: url.path) { return true }
            usleep(100_000)
        }
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func remainsRunning(
        _ process: QuillCodeDesktopLaunchedApplication,
        for duration: TimeInterval
    ) -> Bool {
        guard process.isRunning() else { return false }
        guard duration.isFinite, duration > 0 else { return true }
        let deadline = Date().addingTimeInterval(duration)
        while Date() < deadline {
            usleep(100_000)
            guard process.isRunning() else { return false }
        }
        return process.isRunning()
    }

    static func terminate(_ processID: Int32) {
        guard processID > 1 else { return }
        _ = kill(processID, SIGTERM)
        guard !waitForExit(processID, timeout: 3) else { return }
        _ = kill(processID, SIGKILL)
        _ = waitForExit(processID, timeout: 2)
    }
}
