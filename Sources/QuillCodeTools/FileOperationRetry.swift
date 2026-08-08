import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum FileOperationRetry {
    static let maximumAttempts = 3

    static func run<T>(_ operation: () throws -> T) throws -> T {
        var attempts = 0
        while true {
            do {
                return try operation()
            } catch {
                attempts += 1
                guard attempts < maximumAttempts, isInterrupted(error) else {
                    throw error
                }
            }
        }
    }

    static func isInterrupted(_ error: Error, remainingDepth: Int = 4) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(EINTR) {
            return true
        }
        guard remainingDepth > 0,
              let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? Error else {
            return false
        }
        return isInterrupted(underlyingError, remainingDepth: remainingDepth - 1)
    }
}
