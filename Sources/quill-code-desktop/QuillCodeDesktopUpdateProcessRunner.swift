import Foundation
import QuillCodePlatform

struct QuillCodeDesktopUpdateProcessResult: Sendable {
    var exitCode: Int32
    var standardOutput: String
    var standardError: String
    var outputWasTruncated: Bool

    var combinedOutput: String {
        [standardOutput, standardError].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    var failureSummary: String {
        let value = combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = value.isEmpty ? "the system extraction tool failed" : String(value.suffix(500))
        return outputWasTruncated ? "\(summary) [system-tool output truncated]" : summary
    }
}

enum QuillCodeDesktopUpdateProcessRunner {
    static let defaultTimeout: TimeInterval = 120
    static let extractionTimeout: TimeInterval = 10 * 60
    private static let outputByteLimit = 64 * 1_024
    private static let terminationGrace: TimeInterval = 0.5
    private static let runner = BoundedSubprocessRunner()

    static func run(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval = defaultTimeout
    ) throws -> QuillCodeDesktopUpdateProcessResult {
        do {
            return try processResult(runner.runBlocking(request(
                executableURL: executableURL,
                arguments: arguments,
                timeout: timeout
            )))
        } catch {
            throw mappedError(error)
        }
    }

    static func runAsync(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval = defaultTimeout
    ) async throws -> QuillCodeDesktopUpdateProcessResult {
        do {
            return try processResult(await runner.run(request(
                executableURL: executableURL,
                arguments: arguments,
                timeout: timeout
            )))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw mappedError(error)
        }
    }

    private static func request(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval
    ) -> BoundedSubprocessRequest {
        BoundedSubprocessRequest(
            executableURL: executableURL,
            arguments: arguments,
            timeout: timeout,
            terminationGrace: terminationGrace,
            standardOutputLimit: outputByteLimit,
            standardErrorLimit: outputByteLimit
        )
    }

    private static func processResult(
        _ result: BoundedSubprocessResult
    ) throws -> QuillCodeDesktopUpdateProcessResult {
        guard result.standardOutput.readCompleted,
              result.standardError.readCompleted
        else {
            throw QuillCodeDesktopUpdateError.installationFailed(
                "system-tool output could not be read completely"
            )
        }
        return QuillCodeDesktopUpdateProcessResult(
            exitCode: result.exitCode,
            standardOutput: String(decoding: result.standardOutput.data, as: UTF8.self),
            standardError: String(decoding: result.standardError.data, as: UTF8.self),
            outputWasTruncated: result.standardOutput.wasTruncated || result.standardError.wasTruncated
        )
    }

    private static func mappedError(_ error: any Error) -> any Error {
        guard let processError = error as? BoundedSubprocessError else { return error }
        switch processError {
        case .timedOut:
            return QuillCodeDesktopUpdateError.installationFailed("a required system tool timed out")
        case .executableUnavailable, .launchFailed:
            return QuillCodeDesktopUpdateError.installationFailed(
                "a required system tool could not start"
            )
        case .invalidRequest:
            return QuillCodeDesktopUpdateError.installationFailed(
                "a required system tool was configured incorrectly"
            )
        }
    }
}
