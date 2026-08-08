import Foundation
import XCTest

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@testable import QuillCodeTools

final class FileOperationRetryTests: XCTestCase {
    func testRetriesNestedInterruptedErrorsUntilSuccess() throws {
        var attempts = 0

        let value = try FileOperationRetry.run {
            attempts += 1
            if attempts < FileOperationRetry.maximumAttempts {
                throw nestedInterruptedError()
            }
            return "complete"
        }

        XCTAssertEqual(value, "complete")
        XCTAssertEqual(attempts, FileOperationRetry.maximumAttempts)
    }

    func testDoesNotRetryNonInterruptedErrors() {
        var attempts = 0
        let failure = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)

        XCTAssertThrowsError(
            try FileOperationRetry.run {
                attempts += 1
                throw failure
            } as Void
        )
        XCTAssertEqual(attempts, 1)
    }

    func testStopsAfterMaximumInterruptedAttempts() {
        var attempts = 0

        XCTAssertThrowsError(
            try FileOperationRetry.run {
                attempts += 1
                throw nestedInterruptedError()
            } as Void
        )
        XCTAssertEqual(attempts, FileOperationRetry.maximumAttempts)
    }

    func testRecognizesOnlyBoundedUnderlyingErrorChains() {
        let deepError = (0..<6).reduce(
            NSError(domain: NSPOSIXErrorDomain, code: Int(EINTR))
        ) { error, _ in
            NSError(
                domain: NSCocoaErrorDomain,
                code: NSFileReadUnknownError,
                userInfo: [NSUnderlyingErrorKey: error]
            )
        }

        XCTAssertFalse(FileOperationRetry.isInterrupted(deepError))
        XCTAssertTrue(FileOperationRetry.isInterrupted(nestedInterruptedError()))
    }

    private func nestedInterruptedError() -> NSError {
        NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileReadUnknownError,
            userInfo: [
                NSUnderlyingErrorKey: NSError(
                    domain: NSPOSIXErrorDomain,
                    code: Int(EINTR)
                )
            ]
        )
    }
}
