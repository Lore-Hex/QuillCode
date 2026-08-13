import Foundation
import XCTest
import QuillCodeApp
import QuillCodeCore
@testable import quill_code_desktop

@MainActor
final class QuillCodeDesktopMemoryPressureControllerTests: XCTestCase {
    func testObservationStartsOnceAndRoutesEventsToTheModel() {
        let model = QuillCodeWorkspaceModel()
        let factory = FakeMemoryPressureObservationFactory()
        var refreshCount = 0
        let controller = QuillCodeDesktopMemoryPressureController(
            model: model,
            observationFactory: factory,
            onReclamation: { refreshCount += 1 }
        )

        controller.start()
        controller.start()
        factory.observation?.emit(.warning)

        XCTAssertEqual(factory.makeCount, 1)
        XCTAssertEqual(controller.handledEventCount, 1)
        XCTAssertEqual(refreshCount, 1)
        XCTAssertNotNil(controller.lastReclamation)

        controller.stop()
        XCTAssertEqual(factory.observation?.cancelCount, 1)
    }

    func testCriticalPressureReclaimsLanguageServicesOffActorWhenIdle() async {
        let counter = LockedCounter()
        let controller = QuillCodeDesktopMemoryPressureController(
            model: QuillCodeWorkspaceModel(),
            observationFactory: FakeMemoryPressureObservationFactory(),
            languageServiceReclaimer: { counter.increment() }
        )

        controller.handle(.critical)
        await controller.waitForLanguageServiceReclamation()

        XCTAssertEqual(counter.value, 1)
    }

    func testCriticalPressureDoesNotInterruptLanguageServicesDuringActiveRun() async {
        let thread = ChatThread(title: "Running")
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id),
            agentRuns: WorkspaceAgentRunRegistry(statusesByThreadID: [thread.id: "Running"])
        )
        let counter = LockedCounter()
        let controller = QuillCodeDesktopMemoryPressureController(
            model: model,
            observationFactory: FakeMemoryPressureObservationFactory(),
            languageServiceReclaimer: { counter.increment() }
        )

        controller.handle(.critical)
        await controller.waitForLanguageServiceReclamation()

        XCTAssertEqual(counter.value, 0)
        XCTAssertFalse(try! XCTUnwrap(controller.lastReclamation).shouldReleaseLanguageServices)
    }
}

@MainActor
private final class FakeMemoryPressureObservationFactory:
    QuillCodeDesktopMemoryPressureObservationFactory {
    private(set) var makeCount = 0
    private(set) var observation: FakeMemoryPressureObservation?

    func makeObservation(
        handler: @escaping QuillCodeDesktopMemoryPressureHandler
    ) -> any QuillCodeDesktopMemoryPressureObservation {
        makeCount += 1
        let observation = FakeMemoryPressureObservation(handler: handler)
        self.observation = observation
        return observation
    }
}

private final class FakeMemoryPressureObservation:
    QuillCodeDesktopMemoryPressureObservation,
    @unchecked Sendable {
    private let handler: QuillCodeDesktopMemoryPressureHandler
    private let lock = NSLock()
    private var storedCancelCount = 0

    init(handler: @escaping QuillCodeDesktopMemoryPressureHandler) {
        self.handler = handler
    }

    var cancelCount: Int {
        lock.withLock { storedCancelCount }
    }

    @MainActor
    func emit(_ level: WorkspaceMemoryPressureLevel) {
        handler(level)
    }

    func cancel() {
        lock.withLock {
            storedCancelCount += 1
        }
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = 0

    var value: Int {
        lock.withLock { storedValue }
    }

    func increment() {
        lock.withLock {
            storedValue += 1
        }
    }
}
