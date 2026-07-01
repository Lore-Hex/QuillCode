import XCTest
import Foundation
import QuillCodeCore
@testable import QuillCodeAgent

// MARK: - Unit: fingerprint normalization

final class ToolCallFingerprintTests: XCTestCase {
    func testWhitespaceVariantsHashEqual() {
        let a = ToolCallFingerprint.make(name: "host.shell.run", argumentsJSON: #"{"cmd":"swift  test"}"#)
        let b = ToolCallFingerprint.make(name: "host.shell.run", argumentsJSON: #"{"cmd":"swift test"}"#)
        XCTAssertEqual(a, b)
    }

    func testKeyOrderIsIrrelevant() {
        let a = ToolCallFingerprint.make(name: "t", argumentsJSON: #"{"a":1,"b":2}"#)
        let b = ToolCallFingerprint.make(name: "t", argumentsJSON: #"{"b":2,"a":1}"#)
        XCTAssertEqual(a, b)
    }

    func testAbsoluteAndWorkspaceRelativePathsHashEqual() {
        let root = URL(fileURLWithPath: "/tmp/ws")
        let a = ToolCallFingerprint.make(name: "host.file.read", argumentsJSON: #"{"path":"/tmp/ws/Sources/App.swift"}"#, workspaceRoot: root)
        let b = ToolCallFingerprint.make(name: "host.file.read", argumentsJSON: #"{"path":"Sources/App.swift"}"#, workspaceRoot: root)
        XCTAssertEqual(a, b)
    }

    func testDifferentArgumentsDiffer() {
        let a = ToolCallFingerprint.make(name: "host.shell.run", argumentsJSON: #"{"cmd":"swift test"}"#)
        let b = ToolCallFingerprint.make(name: "host.shell.run", argumentsJSON: #"{"cmd":"swift build"}"#)
        XCTAssertNotEqual(a, b)
    }

    func testDifferentToolNamesDiffer() {
        let a = ToolCallFingerprint.make(name: "host.file.read", argumentsJSON: "{}")
        let b = ToolCallFingerprint.make(name: "host.file.list", argumentsJSON: "{}")
        XCTAssertNotEqual(a, b)
    }

    func testMalformedJSONStillFingerprintsStably() {
        let a = ToolCallFingerprint.make(name: "t", argumentsJSON: "not json  at all")
        let b = ToolCallFingerprint.make(name: "t", argumentsJSON: "not json at all")
        XCTAssertEqual(a, b)
    }
}

// MARK: - Unit: failure signatures

final class FlailSignaturesTests: XCTestCase {
    func testIdenticalFailureTextSameSignature() {
        let output = "Test Case 'X.testFoo' failed (0.132 seconds).\nerror: fatalError\n"
        XCTAssertEqual(
            FlailSignatures.failureSignature(fromToolOutput: output),
            FlailSignatures.failureSignature(fromToolOutput: output)
        )
    }

    func testDurationNoiseDoesNotChangeSignature() {
        let a = FlailSignatures.failureSignature(fromToolOutput: "Test Case 'X.testFoo' failed (0.132 seconds).")
        let b = FlailSignatures.failureSignature(fromToolOutput: "Test Case 'X.testFoo' failed (1.845 seconds).")
        XCTAssertEqual(a, b)
    }

    func testDifferentFailingTestDiffers() {
        let a = FlailSignatures.failureSignature(fromToolOutput: "Test Case 'X.testFoo' failed (0.1 seconds).")
        let b = FlailSignatures.failureSignature(fromToolOutput: "Test Case 'X.testBar' failed (0.1 seconds).")
        XCTAssertNotEqual(a, b)
    }

    func testLineNumbersAreKeptAsIdentity() {
        let a = FlailSignatures.failureSignature(fromToolOutput: "error: patch failed: App.swift:10")
        let b = FlailSignatures.failureSignature(fromToolOutput: "error: patch failed: App.swift:20")
        XCTAssertNotEqual(a, b)
        XCTAssertTrue(a!.contains("App.swift:10"), a!)
    }

    func testCleanOutputHasNoSignature() {
        XCTAssertNil(FlailSignatures.failureSignature(fromToolOutput: "Build complete! (6.3s)\nAll tests passed.\n"))
    }
}

// MARK: - Unit: detector rules

final class FlailDetectorTests: XCTestCase {
    private let testsCall = ToolCallFingerprint.make(name: "host.shell.run", argumentsJSON: #"{"cmd":"swift test"}"#)
    private let build = ToolCallFingerprint.make(name: "host.shell.run", argumentsJSON: #"{"cmd":"swift build"}"#)

    func testRepeatedActionWithZeroDeltaIsSuspected() {
        var detector = FlailDetector(repeatThreshold: 3)
        XCTAssertEqual(detector.record(.init(fingerprints: [testsCall])), .none)
        XCTAssertEqual(detector.record(.init(fingerprints: [testsCall])), .none)
        guard case .suspected(let reason) = detector.record(.init(fingerprints: [testsCall])) else {
            return XCTFail("third identical zero-delta turn must be suspected")
        }
        XCTAssertEqual(reason.kind, .repeatedActionNoProgress)
        XCTAssertTrue(reason.message.contains("3×"), reason.message)
    }

    func testRepeatedActionWithFreshDeltasIsLegitRetry() {
        var detector = FlailDetector(repeatThreshold: 3)
        // Same command each turn but the workspace changes every time — that's iteration, not flail.
        XCTAssertEqual(detector.record(.init(fingerprints: [testsCall], deltaSignature: "d1")), .none)
        XCTAssertEqual(detector.record(.init(fingerprints: [testsCall], deltaSignature: "d2")), .none)
        XCTAssertEqual(detector.record(.init(fingerprints: [testsCall], deltaSignature: "d3")), .none)
    }

    func testRepeatedIdenticalFailureIsSuspected() {
        var detector = FlailDetector(repeatThreshold: 3)
        let failure = "Test Case 'X.testFoo' failed"
        // Different edits each turn (different fingerprints/deltas) but the identical failure persists.
        XCTAssertEqual(detector.record(.init(fingerprints: [build], deltaSignature: "d1", failureSignature: failure)), .none)
        XCTAssertEqual(detector.record(.init(fingerprints: [testsCall], deltaSignature: "d2", failureSignature: failure)), .none)
        guard case .suspected(let reason) = detector.record(.init(fingerprints: [build], deltaSignature: "d3", failureSignature: failure)) else {
            return XCTFail("third identical failure must be suspected")
        }
        XCTAssertEqual(reason.kind, .repeatedFailure)
        XCTAssertTrue(reason.message.contains("testFoo"), reason.message)
    }

    func testPingPongAlternationIsSuspected() {
        var detector = FlailDetector(repeatThreshold: 3)
        XCTAssertEqual(detector.record(.init(fingerprints: [build], deltaSignature: "A")), .none)
        XCTAssertEqual(detector.record(.init(fingerprints: [build], deltaSignature: "B")), .none)
        XCTAssertEqual(detector.record(.init(fingerprints: [build], deltaSignature: "A")), .none)
        guard case .suspected(let reason) = detector.record(.init(fingerprints: [build], deltaSignature: "B")) else {
            return XCTFail("A,B,A,B must be suspected")
        }
        XCTAssertEqual(reason.kind, .pingPong)
    }

    func testEscalatesToConfirmedOnlyAfterAssessment() {
        var detector = FlailDetector(repeatThreshold: 3)
        _ = detector.record(.init(fingerprints: [testsCall]))
        _ = detector.record(.init(fingerprints: [testsCall]))
        guard case .suspected = detector.record(.init(fingerprints: [testsCall])) else {
            return XCTFail("expected suspected")
        }
        // WITHOUT an assessment, more flail stays suspected (the wiring hasn't intervened yet).
        guard case .suspected = detector.record(.init(fingerprints: [testsCall])) else {
            return XCTFail("still suspected before assessment")
        }
        detector.recordAssessment()
        guard case .confirmed(let reason) = detector.record(.init(fingerprints: [testsCall])) else {
            return XCTFail("flail persisting past the assessment must be confirmed")
        }
        XCTAssertEqual(reason.kind, .repeatedActionNoProgress)
    }

    func testGenuineProgressClearsTheAssessmentStrike() {
        var detector = FlailDetector(repeatThreshold: 3)
        _ = detector.record(.init(fingerprints: [testsCall]))
        _ = detector.record(.init(fingerprints: [testsCall]))
        _ = detector.record(.init(fingerprints: [testsCall]))              // suspected
        detector.recordAssessment()
        XCTAssertEqual(detector.record(.init(fingerprints: [build], deltaSignature: "progress")), .none)

        // A NEW flail episode later must start over at suspected, not jump to confirmed.
        _ = detector.record(.init(fingerprints: [testsCall]))
        _ = detector.record(.init(fingerprints: [testsCall]))
        guard case .suspected = detector.record(.init(fingerprints: [testsCall])) else {
            return XCTFail("post-progress episode must restart at suspected")
        }
    }

    func testProgressBreaksConsecutivenessAndResetsTheWindow() {
        var detector = FlailDetector(repeatThreshold: 3)
        _ = detector.record(.init(fingerprints: [testsCall]))
        _ = detector.record(.init(fingerprints: [testsCall]))
        XCTAssertEqual(detector.record(.init(fingerprints: [build], deltaSignature: "d1")), .none)
        // Two more zero-delta repeats are NOT enough — the window restarted.
        _ = detector.record(.init(fingerprints: [testsCall]))
        XCTAssertEqual(detector.record(.init(fingerprints: [testsCall])), .none)
    }

    func testEmptyFingerprintTurnsNeverMatchTheActionRule() {
        var detector = FlailDetector(repeatThreshold: 3)
        XCTAssertEqual(detector.record(.init(fingerprints: [])), .none)
        XCTAssertEqual(detector.record(.init(fingerprints: [])), .none)
        XCTAssertEqual(detector.record(.init(fingerprints: [])), .none)
    }
}

// MARK: - Functional: scripted transcript-shaped scenarios

final class FlailDetectorScenarioTests: XCTestCase {
    func testOvernightTestLoopScenario() {
        // The canonical nightmare: `swift test` on repeat, identical failure, nothing changing.
        var detector = FlailDetector()
        let call = ToolCall(name: "host.shell.run", argumentsJSON: #"{"cmd":"swift test --filter FooTests"}"#)
        let fingerprint = ToolCallFingerprint.make(call: call)
        let failure = FlailSignatures.failureSignature(
            fromToolOutput: "Test Case 'FooTests.testBar' failed (0.4 seconds).\nerror: fatalError in Foo.swift"
        )

        var verdicts: [FlailVerdict] = []
        for _ in 1...3 {
            verdicts.append(detector.record(.init(fingerprints: [fingerprint], deltaSignature: "", failureSignature: failure)))
        }
        guard case .suspected(let reason) = verdicts.last else {
            return XCTFail("three identical no-progress test runs must be suspected")
        }
        XCTAssertFalse(reason.message.isEmpty)

        detector.recordAssessment()
        guard case .confirmed = detector.record(.init(fingerprints: [fingerprint], deltaSignature: "", failureSignature: failure)) else {
            return XCTFail("persisting past assessment must confirm")
        }
    }

    func testHealthyIterationScenarioStaysQuiet() {
        // Edit → test → edit → test with fresh deltas and changing failures: a healthy debugging loop.
        var detector = FlailDetector()
        let edit = ToolCallFingerprint.make(name: "host.apply_patch", argumentsJSON: #"{"patch":"..."}"#)
        let test = ToolCallFingerprint.make(name: "host.shell.run", argumentsJSON: #"{"cmd":"swift test"}"#)

        XCTAssertEqual(detector.record(.init(fingerprints: [edit], deltaSignature: "d1")), .none)
        XCTAssertEqual(detector.record(.init(fingerprints: [test], deltaSignature: "", failureSignature: "fail A")), .none)
        XCTAssertEqual(detector.record(.init(fingerprints: [edit], deltaSignature: "d2")), .none)
        XCTAssertEqual(detector.record(.init(fingerprints: [test], deltaSignature: "", failureSignature: "fail B")), .none)
        XCTAssertEqual(detector.record(.init(fingerprints: [edit], deltaSignature: "d3")), .none)
        XCTAssertEqual(detector.record(.init(fingerprints: [test], deltaSignature: "")), .none)
    }
}
