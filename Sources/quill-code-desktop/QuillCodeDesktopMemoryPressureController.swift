import Dispatch
import Foundation
import QuillCodeApp

typealias QuillCodeDesktopMemoryPressureHandler =
    @MainActor @Sendable (WorkspaceMemoryPressureLevel) -> Void

protocol QuillCodeDesktopMemoryPressureObservation: Sendable {
    func cancel()
}

@MainActor
protocol QuillCodeDesktopMemoryPressureObservationFactory {
    func makeObservation(
        handler: @escaping QuillCodeDesktopMemoryPressureHandler
    ) -> any QuillCodeDesktopMemoryPressureObservation
}

struct QuillCodeDesktopSystemMemoryPressureObservationFactory:
    QuillCodeDesktopMemoryPressureObservationFactory {
    func makeObservation(
        handler: @escaping QuillCodeDesktopMemoryPressureHandler
    ) -> any QuillCodeDesktopMemoryPressureObservation {
        #if os(macOS)
        QuillCodeDesktopDispatchMemoryPressureObservation(handler: handler)
        #else
        QuillCodeDesktopInactiveMemoryPressureObservation()
        #endif
    }
}

@MainActor
final class QuillCodeDesktopMemoryPressureController {
    private let model: QuillCodeWorkspaceModel
    private let observationFactory: any QuillCodeDesktopMemoryPressureObservationFactory
    private let languageServiceReclaimer: @Sendable () -> Void
    private let onReclamation: @MainActor () -> Void
    private var observation: (any QuillCodeDesktopMemoryPressureObservation)?
    private var languageServiceReclamationTask: Task<Void, Never>?
    private var languageServiceReclamationGeneration = 0

    private(set) var handledEventCount = 0
    private(set) var lastReclamation: WorkspaceMemoryReclamation?

    convenience init(owner: QuillCodeDesktopController) {
        self.init(model: owner.model, onReclamation: { [weak owner] in owner?.refresh() })
    }

    init(
        model: QuillCodeWorkspaceModel,
        observationFactory: any QuillCodeDesktopMemoryPressureObservationFactory =
            QuillCodeDesktopSystemMemoryPressureObservationFactory(),
        languageServiceReclaimer: @escaping @Sendable () -> Void = {
            WorkspaceLSPCoordinatorProvider.shared.shutdownAll()
        },
        onReclamation: @escaping @MainActor () -> Void = {}
    ) {
        self.model = model
        self.observationFactory = observationFactory
        self.languageServiceReclaimer = languageServiceReclaimer
        self.onReclamation = onReclamation
    }

    func start() {
        guard observation == nil else { return }
        observation = observationFactory.makeObservation { [weak self] level in
            self?.handle(level)
        }
    }

    func stop() {
        observation?.cancel()
        observation = nil
    }

    func handle(_ level: WorkspaceMemoryPressureLevel) {
        handledEventCount += 1
        let reclamation = model.releaseReconstructibleMemory(for: level)
        lastReclamation = reclamation
        onReclamation()

        guard reclamation.shouldReleaseLanguageServices,
              languageServiceReclamationTask == nil
        else { return }

        languageServiceReclamationGeneration &+= 1
        let generation = languageServiceReclamationGeneration
        let reclaimer = languageServiceReclaimer
        let task = Task.detached(priority: .utility) {
            reclaimer()
        }
        languageServiceReclamationTask = task
        Task { [weak self] in
            await task.value
            guard let self, self.languageServiceReclamationGeneration == generation else { return }
            self.languageServiceReclamationTask = nil
        }
    }

    func waitForLanguageServiceReclamation() async {
        await languageServiceReclamationTask?.value
    }
}

#if os(macOS)
private final class QuillCodeDesktopDispatchMemoryPressureObservation:
    QuillCodeDesktopMemoryPressureObservation,
    @unchecked Sendable {
    private let source: DispatchSourceMemoryPressure
    private let handler: QuillCodeDesktopMemoryPressureHandler
    private let lock = NSLock()
    private var isCancelled = false

    init(handler: @escaping QuillCodeDesktopMemoryPressureHandler) {
        self.handler = handler
        source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: DispatchQueue(label: "com.lorehex.quillcowork.memory-pressure", qos: .utility)
        )
        source.setEventHandler { [weak self] in
            self?.deliverCurrentEvent()
        }
        source.activate()
    }

    deinit {
        cancel()
    }

    func cancel() {
        lock.lock()
        guard !isCancelled else {
            lock.unlock()
            return
        }
        isCancelled = true
        lock.unlock()
        source.cancel()
    }

    private func deliverCurrentEvent() {
        let event = source.data
        let level: WorkspaceMemoryPressureLevel
        if event.contains(.critical) {
            level = .critical
        } else if event.contains(.warning) {
            level = .warning
        } else {
            return
        }
        let handler = handler
        Task { @MainActor in
            handler(level)
        }
    }
}
#else
private struct QuillCodeDesktopInactiveMemoryPressureObservation:
    QuillCodeDesktopMemoryPressureObservation {
    func cancel() {}
}
#endif
