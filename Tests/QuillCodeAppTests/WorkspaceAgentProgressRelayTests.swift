import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceAgentProgressRelayTests: XCTestCase {
    func testRelayDoesNotBlockProducerAndKeepsOnlyNewestPendingSnapshot() async throws {
        let gate = WorkspaceAgentProgressRelayGate()
        let recorder = WorkspaceAgentProgressRelayRecorder()
        let first = ChatThread(title: "first")
        let second = ChatThread(title: "second")
        let newest = ChatThread(title: "newest")
        let relay = WorkspaceAgentProgressRelay { thread in
            await recorder.append(thread.title)
            if thread.id == first.id {
                await gate.wait()
            }
        }

        relay.publish(first)
        try await waitUntil { await recorder.titles() == ["first"] }

        relay.publish(second)
        relay.publish(newest)
        let titlesWhileBlocked = await recorder.titles()
        XCTAssertEqual(titlesWhileBlocked, ["first"])

        await gate.open()
        relay.finish()
        await relay.waitUntilFinished()

        let finalTitles = await recorder.titles()
        XCTAssertEqual(finalTitles, ["first", "newest"])
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        condition: @escaping @Sendable () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for relay state")
    }
}

private actor WorkspaceAgentProgressRelayGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

private actor WorkspaceAgentProgressRelayRecorder {
    private var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }

    func titles() -> [String] {
        values
    }
}
