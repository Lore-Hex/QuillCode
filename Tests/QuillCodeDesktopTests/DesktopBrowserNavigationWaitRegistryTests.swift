import XCTest
@testable import quill_code_desktop

@MainActor
final class DesktopBrowserNavigationWaitRegistryTests: XCTestCase {
    private final class NavigationToken {}

    func testMatchingNavigationCompletesAndReleasesWaiter() async throws {
        let registry = DesktopBrowserNavigationWaitRegistry(timeoutNanoseconds: 5_000_000_000)
        let tabID = UUID()
        let navigation = NavigationToken()

        let task = Task { @MainActor in
            try await registry.wait(for: tabID) { navigation }
        }
        await Task.yield()

        XCTAssertEqual(registry.activeCount, 1)
        XCTAssertTrue(registry.resolve(for: tabID, navigation: navigation, error: nil))
        try await task.value
        XCTAssertEqual(registry.activeCount, 0)
        XCTAssertFalse(registry.resolve(for: tabID, navigation: navigation, error: nil))
    }

    func testNewNavigationSupersedesOldAndIgnoresItsLateCallback() async throws {
        let registry = DesktopBrowserNavigationWaitRegistry(timeoutNanoseconds: 5_000_000_000)
        let tabID = UUID()
        let oldNavigation = NavigationToken()
        let newNavigation = NavigationToken()

        let oldTask = Task { @MainActor in
            try await registry.wait(for: tabID) { oldNavigation }
        }
        await Task.yield()
        let newTask = Task { @MainActor in
            try await registry.wait(for: tabID) { newNavigation }
        }
        await Task.yield()

        await assertThrows(.navigationSuperseded, from: oldTask)
        XCTAssertEqual(registry.activeCount, 1)
        XCTAssertFalse(registry.resolve(for: tabID, navigation: oldNavigation, error: nil))
        XCTAssertFalse(registry.resolve(for: tabID, navigation: nil, error: nil))
        XCTAssertEqual(registry.activeCount, 1)
        XCTAssertTrue(registry.resolve(for: tabID, navigation: newNavigation, error: nil))
        try await newTask.value
        XCTAssertEqual(registry.activeCount, 0)
    }

    func testCancellationPromptlyReleasesWaiterWithoutTouchingReplacement() async throws {
        let registry = DesktopBrowserNavigationWaitRegistry(timeoutNanoseconds: 5_000_000_000)
        let tabID = UUID()
        let cancelledNavigation = NavigationToken()

        let cancelledTask = Task { @MainActor in
            try await registry.wait(for: tabID) { cancelledNavigation }
        }
        await Task.yield()
        cancelledTask.cancel()

        do {
            try await cancelledTask.value
            XCTFail("Expected navigation cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(registry.activeCount, 0)

        let replacementNavigation = NavigationToken()
        let replacementTask = Task { @MainActor in
            try await registry.wait(for: tabID) { replacementNavigation }
        }
        await Task.yield()
        XCTAssertFalse(registry.resolve(for: tabID, navigation: cancelledNavigation, error: nil))
        XCTAssertTrue(registry.resolve(for: tabID, navigation: replacementNavigation, error: nil))
        try await replacementTask.value
    }

    func testTimeoutCapturesPartialPageAndReleasesWaiter() async throws {
        let registry = DesktopBrowserNavigationWaitRegistry(timeoutNanoseconds: 1_000_000)
        let tabID = UUID()

        try await registry.wait(for: tabID) { NavigationToken() }

        XCTAssertEqual(registry.activeCount, 0)
    }

    func testTabAndWindowClosureFailAllAffectedWaiters() async {
        let registry = DesktopBrowserNavigationWaitRegistry(timeoutNanoseconds: 5_000_000_000)
        let firstTabID = UUID()
        let secondTabID = UUID()
        let firstTask = Task { @MainActor in
            try await registry.wait(for: firstTabID) { NavigationToken() }
        }
        let secondTask = Task { @MainActor in
            try await registry.wait(for: secondTabID) { NavigationToken() }
        }
        await Task.yield()

        XCTAssertTrue(registry.finish(tabID: firstTabID, error: DesktopBrowserSessionScriptError.noSelectedTab))
        await assertThrows(.noSelectedTab, from: firstTask)
        XCTAssertEqual(registry.activeCount, 1)

        registry.finishAll(error: DesktopBrowserSessionScriptError.noOpenSession)
        await assertThrows(.noOpenSession, from: secondTask)
        XCTAssertEqual(registry.activeCount, 0)
    }

    func testRapidReplacementKeepsOnlyOneWaiterAndOneWinningNavigation() async throws {
        let registry = DesktopBrowserNavigationWaitRegistry(timeoutNanoseconds: 5_000_000_000)
        let tabID = UUID()
        var tasks: [Task<Void, any Error>] = []
        var winningNavigation: NavigationToken?

        for _ in 0..<1_000 {
            let navigation = NavigationToken()
            winningNavigation = navigation
            tasks.append(Task { @MainActor in
                try await registry.wait(for: tabID) { navigation }
            })
            await Task.yield()
            XCTAssertLessThanOrEqual(registry.activeCount, 1)
        }

        for task in tasks.dropLast() {
            await assertThrows(.navigationSuperseded, from: task)
        }
        let winner = try XCTUnwrap(winningNavigation)
        XCTAssertTrue(registry.resolve(for: tabID, navigation: winner, error: nil))
        try await tasks.last?.value
        XCTAssertEqual(registry.activeCount, 0)
    }

    private func assertThrows(
        _ expected: DesktopBrowserSessionScriptError,
        from task: Task<Void, any Error>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await task.value
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as DesktopBrowserSessionScriptError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}
