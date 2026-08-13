import Foundation
@testable import QuillCodePlatform
import XCTest

final class BoundedSubprocessRunnerTests: XCTestCase {
    private let runner = BoundedSubprocessRunner()

    func testContinuouslyDrainsNoisyOutputWhileRetainingBoundedPrefix() async throws {
        let result = try await runner.run(request(
            script: """
            i=0
            while [ "$i" -lt 10000 ]; do
              printf '0123456789abcdef0123456789abcdef\\n'
              i=$((i + 1))
            done
            """,
            outputLimit: 4_096
        ))

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.standardOutput.readCompleted)
        XCTAssertTrue(result.standardOutput.wasTruncated)
        XCTAssertEqual(result.standardOutput.data.count, 4_096)
        XCTAssertEqual(result.standardOutput.totalByteCount, 330_000)
        XCTAssertTrue(String(decoding: result.standardOutput.data, as: UTF8.self).hasPrefix("012345"))
    }

    func testRetainsDiagnosticSuffixWhenStandardErrorIsTruncated() async throws {
        let result = try await runner.run(request(
            script: """
            i=0
            while [ "$i" -lt 5000 ]; do
              printf 'repeated diagnostic %04d\\n' "$i" >&2
              i=$((i + 1))
            done
            printf 'FINAL_DIAGNOSTIC\\n' >&2
            """,
            errorLimit: 128
        ))
        let retainedError = String(decoding: result.standardError.data, as: UTF8.self)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.standardError.readCompleted)
        XCTAssertTrue(result.standardError.wasTruncated)
        XCTAssertEqual(result.standardError.data.count, 128)
        XCTAssertTrue(retainedError.hasSuffix("FINAL_DIAGNOSTIC\n"))
    }

    func testTimeoutTracksProcessExitEvenAfterChildClosesOutputPipes() async throws {
        let started = Date()

        do {
            _ = try await runner.run(request(
                script: "exec 1>&- 2>&-; trap '' TERM; while :; do :; done",
                timeout: 0.1,
                terminationGrace: 0.1
            ))
            XCTFail("Expected the subprocess to time out")
        } catch let error as BoundedSubprocessError {
            XCTAssertEqual(error, .timedOut)
        }

        let elapsed = Date().timeIntervalSince(started)
        XCTAssertGreaterThanOrEqual(elapsed, 0.08)
        XCTAssertLessThan(elapsed, 1)
    }

    func testCancellationForceKillsTermResistantChild() async throws {
        let runner = runner
        let processRequest = request(
            script: "trap '' TERM; while :; do :; done",
            timeout: 30,
            terminationGrace: 0.1
        )
        let task = Task {
            try await runner.run(processRequest)
        }
        try await Task.sleep(for: .milliseconds(100))
        let cancelledAt = Date()
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }
        XCTAssertLessThan(Date().timeIntervalSince(cancelledAt), 1)
    }

    func testReturnsIncompleteCaptureWhenDescendantKeepsPipesOpen() async throws {
        let started = Date()
        let result = try await runner.run(request(
            script: "(while :; do printf x; /bin/sleep 0.05; done) & exit 0",
            terminationGrace: 0.05
        ))

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
        XCTAssertFalse(
            result.standardOutput.readCompleted && result.standardError.readCompleted,
            "A descendant-held pipe must not keep the caller waiting for EOF"
        )
    }

    func testRejectsUnavailableExecutableBeforeLaunch() {
        XCTAssertThrowsError(try runner.runBlocking(BoundedSubprocessRequest(
            executableURL: URL(fileURLWithPath: "/definitely/missing/quill-cowork-tool"),
            timeout: 1
        ))) { error in
            XCTAssertEqual(error as? BoundedSubprocessError, .executableUnavailable)
        }
    }

    private func request(
        script: String,
        timeout: TimeInterval = 5,
        terminationGrace: TimeInterval = 0.2,
        outputLimit: Int = 1_024,
        errorLimit: Int = 1_024
    ) -> BoundedSubprocessRequest {
        BoundedSubprocessRequest(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            timeout: timeout,
            terminationGrace: terminationGrace,
            standardOutputLimit: outputLimit,
            standardErrorLimit: errorLimit
        )
    }
}
