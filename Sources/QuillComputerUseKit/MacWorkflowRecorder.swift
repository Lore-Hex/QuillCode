#if canImport(AppKit) && canImport(ApplicationServices) && canImport(CoreGraphics)
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

actor MacWorkflowRecorder {
    private let statusStore: MacWorkflowRecordingStatusStore
    private let durationSeconds: TimeInterval
    private let beforeMonitorInstallation: @Sendable () async -> Void

    init(
        statusStore: MacWorkflowRecordingStatusStore,
        durationSeconds: TimeInterval = TimeInterval(WorkflowRecordingLimits.durationSeconds),
        beforeMonitorInstallation: @escaping @Sendable () async -> Void = {}
    ) {
        self.statusStore = statusStore
        self.durationSeconds = max(0.01, durationSeconds)
        self.beforeMonitorInstallation = beforeMonitorInstallation
    }

    private struct Startup {
        var id: UUID
        var request: WorkflowRecordingRequest
    }

    private struct PendingInput {
        var isProtected: Bool
        var text: String
        var characterCount: Int
        var elapsedMilliseconds: Int
        var application: ComputerUseApplication?
    }

    private struct Session {
        var id: UUID
        var request: WorkflowRecordingRequest
        var startedAt: Date
        var events: [WorkflowRecordingEvent]
        var snapshots: [WorkflowRecordingSnapshot]
        var omittedEventCount: Int
        var omittedSnapshotCount: Int
        var pendingInput: PendingInput?
        var lastApplication: ComputerUseApplication?
        var lastSnapshotAt: Date?
        var monitors: MacWorkflowEventMonitors?
        var durationTask: Task<Void, Never>?
        var acceptsEvents: Bool
        var reachedDurationLimit: Bool
    }

    private var startup: Startup?
    private var session: Session?

    func status() -> WorkflowRecordingStatus {
        guard let session else { return statusStore.snapshot }
        let status = WorkflowRecordingStatus(
            phase: session.reachedDurationLimit ? .limitReached : .recording,
            goal: session.request.goal,
            startedAt: session.startedAt,
            eventCount: session.events.count + (session.pendingInput == nil ? 0 : 1),
            snapshotCount: session.snapshots.count
        )
        statusStore.update(status)
        return status
    }

    func start(_ request: WorkflowRecordingRequest) async throws -> WorkflowRecordingStatus {
        guard startup == nil, session == nil else {
            throw ComputerUseError.unavailable("A workflow recording is already in progress.")
        }
        guard !request.goal.isEmpty else {
            throw ComputerUseError.unavailable("Describe the workflow before recording it.")
        }
        guard !request.artifactDirectory.isEmpty else {
            throw ComputerUseError.unavailable("Workflow recording needs a private artifact directory.")
        }

        let artifactDirectory = URL(fileURLWithPath: request.artifactDirectory, isDirectory: true)
        try FileManager.default.createDirectory(
            at: artifactDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: artifactDirectory.path
        )

        let sessionID = UUID()
        startup = Startup(id: sessionID, request: request)
        await beforeMonitorInstallation()
        let monitors = await MainActor.run {
            MacWorkflowEventMonitors { [weak self] input in
                Task { await self?.record(input) }
            }
        }
        guard startup?.id == sessionID, session == nil else {
            await monitors.invalidate()
            Self.removeArtifacts(in: request.artifactDirectory)
            throw ComputerUseError.unavailable("Workflow recording start was cancelled.")
        }

        let startedAt = Date()
        session = Session(
            id: sessionID,
            request: request,
            startedAt: startedAt,
            events: [],
            snapshots: [],
            omittedEventCount: 0,
            omittedSnapshotCount: 0,
            pendingInput: nil,
            lastApplication: nil,
            lastSnapshotAt: nil,
            monitors: monitors,
            durationTask: nil,
            acceptsEvents: true,
            reachedDurationLimit: false
        )
        startup = nil
        let durationNanoseconds = UInt64(durationSeconds * 1_000_000_000)
        session?.durationTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: durationNanoseconds)
            } catch {
                return
            }
            await self?.reachDurationLimit(sessionID: sessionID)
        }
        await captureSnapshot(force: true)
        guard session?.id == sessionID else {
            throw ComputerUseError.unavailable("Workflow recording start was cancelled.")
        }
        let currentStatus = status()
        statusStore.update(currentStatus)
        return currentStatus
    }

    func stop() async throws -> WorkflowRecordingCapture {
        if let activeStartup = startup {
            startup = nil
            statusStore.update(.idle)
            Self.removeArtifacts(in: activeStartup.request.artifactDirectory)
            throw ComputerUseError.unavailable("Workflow recording start was cancelled.")
        }
        guard var activeSession = session else {
            throw ComputerUseError.unavailable("No workflow recording is in progress.")
        }
        session = nil
        activeSession.acceptsEvents = false
        activeSession.durationTask?.cancel()
        activeSession.durationTask = nil
        await activeSession.monitors?.invalidate()
        activeSession.monitors = nil
        Self.flushPendingInput(in: &activeSession)
        session = activeSession
        await captureSnapshot(force: true)
        guard let finishedSession = session else {
            throw ComputerUseError.unavailable("Workflow recording stopped unexpectedly.")
        }
        session = nil
        statusStore.update(.idle)
        return WorkflowRecordingCapture(
            goal: finishedSession.request.goal,
            startedAt: finishedSession.startedAt,
            stoppedAt: Date(),
            originThreadID: finishedSession.request.originThreadID,
            projectID: finishedSession.request.projectID,
            workspaceRoot: finishedSession.request.workspaceRoot,
            events: finishedSession.events,
            snapshots: finishedSession.snapshots,
            omittedEventCount: finishedSession.omittedEventCount,
            omittedSnapshotCount: finishedSession.omittedSnapshotCount,
            reachedDurationLimit: finishedSession.reachedDurationLimit
        )
    }

    func cancel() async {
        if let activeStartup = startup {
            startup = nil
            statusStore.update(.idle)
            Self.removeArtifacts(in: activeStartup.request.artifactDirectory)
            return
        }
        guard let activeSession = session else { return }
        session = nil
        statusStore.update(.idle)
        activeSession.durationTask?.cancel()
        await activeSession.monitors?.invalidate()
        Self.removeArtifacts(in: activeSession.request.artifactDirectory)
    }

    private func record(_ input: MacWorkflowInput) async {
        guard var activeSession = session, activeSession.acceptsEvents else { return }
        let elapsed = max(0, Int(Date().timeIntervalSince(activeSession.startedAt) * 1_000))
        guard elapsed <= Int(durationSeconds * 1_000) else {
            await reachDurationLimit(sessionID: activeSession.id)
            return
        }

        if activeSession.lastApplication != input.application {
            Self.flushPendingInput(in: &activeSession)
            if let application = input.application {
                Self.appendEvent(
                    WorkflowRecordingEvent(
                        kind: .applicationChanged,
                        elapsedMilliseconds: elapsed,
                        summary: "Switched to \(application.displayLabel).",
                        application: application
                    ),
                    to: &activeSession
                )
            }
            activeSession.lastApplication = input.application
        }

        switch input.kind {
        case .click:
            Self.flushPendingInput(in: &activeSession)
            Self.appendEvent(
                WorkflowRecordingEvent(
                    kind: .click,
                    elapsedMilliseconds: elapsed,
                    summary: "Clicked at \(input.x ?? 0), \(input.y ?? 0).",
                    application: input.application,
                    x: input.x,
                    y: input.y
                ),
                to: &activeSession
            )
        case .scroll:
            Self.flushPendingInput(in: &activeSession)
            let direction = Self.scrollDescription(dx: input.dx, dy: input.dy)
            Self.appendEvent(
                WorkflowRecordingEvent(
                    kind: .scroll,
                    elapsedMilliseconds: elapsed,
                    summary: direction,
                    application: input.application
                ),
                to: &activeSession
            )
        case .text:
            Self.appendInput(input, elapsedMilliseconds: elapsed, to: &activeSession)
        case .key:
            Self.flushPendingInput(in: &activeSession)
            Self.appendEvent(
                WorkflowRecordingEvent(
                    kind: .key,
                    elapsedMilliseconds: elapsed,
                    summary: "Pressed \(input.key ?? "a key").",
                    application: input.application
                ),
                to: &activeSession
            )
        }

        session = activeSession
        if input.kind.shouldCaptureSnapshot {
            await captureSnapshot(force: false)
        }
        _ = status()
    }

    private func captureSnapshot(force: Bool) async {
        guard var activeSession = session else { return }
        if activeSession.snapshots.count >= WorkflowRecordingLimits.snapshotCount {
            guard force, let replaced = activeSession.snapshots.popLast() else {
                activeSession.omittedSnapshotCount += 1
                session = activeSession
                return
            }
            activeSession.omittedSnapshotCount += 1
            try? FileManager.default.removeItem(atPath: replaced.path)
        }
        let now = Date()
        if !force,
           let lastSnapshotAt = activeSession.lastSnapshotAt,
           now.timeIntervalSince(lastSnapshotAt) < 1.5 {
            return
        }
        guard let image = CGDisplayCreateImage(CGMainDisplayID()) else { return }
        let target = Self.scaledDimensions(width: image.width, height: image.height)
        guard let scaled = Self.scaledImage(image, width: target.width, height: target.height) else {
            return
        }
        let bitmap = NSBitmapImageRep(cgImage: scaled)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else { return }

        let index = activeSession.snapshots.count + 1
        let url = URL(fileURLWithPath: activeSession.request.artifactDirectory, isDirectory: true)
            .appendingPathComponent(String(format: "workflow-%02d.png", index))
        do {
            try pngData.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            return
        }
        let elapsed = max(0, Int(now.timeIntervalSince(activeSession.startedAt) * 1_000))
        activeSession.snapshots.append(
            WorkflowRecordingSnapshot(
                path: url.path,
                width: scaled.width,
                height: scaled.height,
                elapsedMilliseconds: elapsed,
                application: Self.frontmostApplication()
            )
        )
        activeSession.lastSnapshotAt = now
        session = activeSession
        _ = status()
    }

    private func reachDurationLimit(sessionID: UUID) async {
        guard var activeSession = session,
              activeSession.id == sessionID,
              activeSession.acceptsEvents
        else {
            return
        }
        activeSession.acceptsEvents = false
        activeSession.reachedDurationLimit = true
        activeSession.durationTask = nil
        Self.flushPendingInput(in: &activeSession)
        let monitors = activeSession.monitors
        activeSession.monitors = nil
        session = activeSession
        await monitors?.invalidate()
        await captureSnapshot(force: true)
        _ = status()
    }

    private static func removeArtifacts(in directory: String) {
        try? FileManager.default.removeItem(atPath: directory)
    }

    private static func appendInput(
        _ input: MacWorkflowInput,
        elapsedMilliseconds: Int,
        to session: inout Session
    ) {
        let isProtected = input.isProtected
        if let pending = session.pendingInput,
           pending.isProtected == isProtected,
           pending.application == input.application,
           elapsedMilliseconds - pending.elapsedMilliseconds < 2_000 {
            session.pendingInput?.characterCount += input.characterCount
            if !isProtected {
                let remaining = max(0, 160 - (session.pendingInput?.text.count ?? 0))
                session.pendingInput?.text += String((input.text ?? "").prefix(remaining))
            }
            return
        }

        flushPendingInput(in: &session)
        session.pendingInput = PendingInput(
            isProtected: isProtected,
            text: isProtected ? "" : String((input.text ?? "").prefix(160)),
            characterCount: max(1, input.characterCount),
            elapsedMilliseconds: elapsedMilliseconds,
            application: input.application
        )
    }

    private static func flushPendingInput(in session: inout Session) {
        guard let pending = session.pendingInput else { return }
        session.pendingInput = nil
        let event: WorkflowRecordingEvent
        if pending.isProtected {
            event = WorkflowRecordingEvent(
                kind: .protectedInput,
                elapsedMilliseconds: pending.elapsedMilliseconds,
                summary: "Entered \(pending.characterCount) protected characters (content redacted).",
                application: pending.application
            )
        } else {
            let display = pending.text
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: "\t", with: "\\t")
            let suffix = pending.characterCount > pending.text.count
                ? " (\(pending.characterCount) characters total)"
                : ""
            event = WorkflowRecordingEvent(
                kind: .textInput,
                elapsedMilliseconds: pending.elapsedMilliseconds,
                summary: "Typed \"\(display)\"\(suffix).",
                application: pending.application
            )
        }
        appendEvent(event, to: &session)
    }

    private static func appendEvent(_ event: WorkflowRecordingEvent, to session: inout Session) {
        guard session.events.count < WorkflowRecordingLimits.eventCount else {
            session.omittedEventCount += 1
            return
        }
        session.events.append(event)
    }

    private static func scrollDescription(dx: Int?, dy: Int?) -> String {
        let dx = dx ?? 0
        let dy = dy ?? 0
        if abs(dy) >= abs(dx) {
            return dy < 0 ? "Scrolled down." : "Scrolled up."
        }
        return dx < 0 ? "Scrolled right." : "Scrolled left."
    }

    private static func scaledDimensions(width: Int, height: Int) -> (width: Int, height: Int) {
        let longest = max(width, height)
        guard longest > 1_440 else { return (width, height) }
        let scale = 1_440.0 / Double(longest)
        return (
            max(1, Int((Double(width) * scale).rounded())),
            max(1, Int((Double(height) * scale).rounded()))
        )
    }

    private static func scaledImage(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    fileprivate static func frontmostApplication() -> ComputerUseApplication? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return ComputerUseApplication(
            name: app.localizedName,
            bundleIdentifier: app.bundleIdentifier
        )
    }
}

final class MacWorkflowRecordingStatusStore: @unchecked Sendable {
    private let lock = NSLock()
    private var value: WorkflowRecordingStatus = .idle

    var snapshot: WorkflowRecordingStatus {
        lock.withLock { value }
    }

    func update(_ status: WorkflowRecordingStatus) {
        lock.withLock {
            value = status
        }
    }
}

private struct MacWorkflowInput: Sendable {
    enum Kind: Sendable {
        case click
        case scroll
        case text
        case key

        var shouldCaptureSnapshot: Bool {
            switch self {
            case .click, .scroll, .key:
                return true
            case .text:
                return false
            }
        }
    }

    var kind: Kind
    var application: ComputerUseApplication?
    var x: Int?
    var y: Int?
    var dx: Int?
    var dy: Int?
    var text: String?
    var key: String?
    var characterCount: Int
    var isProtected: Bool

    @MainActor
    init?(event: NSEvent) {
        application = MacWorkflowRecorder.frontmostApplication()
        x = nil
        y = nil
        dx = nil
        dy = nil
        text = nil
        key = nil
        characterCount = 0
        isProtected = false

        switch event.type {
        case .leftMouseDown:
            kind = .click
            let point = NSEvent.mouseLocation
            let screenHeight = NSScreen.screens.first?.frame.height ?? 0
            x = Int(point.x.rounded())
            y = Int((screenHeight - point.y).rounded())
        case .scrollWheel:
            kind = .scroll
            dx = Int(event.scrollingDeltaX.rounded())
            dy = Int(event.scrollingDeltaY.rounded())
        case .keyDown:
            let modifiers = event.modifierFlags.intersection([.command, .control, .option])
            let characters = event.charactersIgnoringModifiers ?? ""
            if modifiers.isEmpty, Self.isPrintable(characters) {
                kind = .text
                isProtected = Self.focusedElementIsProtected()
                text = isProtected ? nil : characters
                characterCount = max(1, characters.count)
            } else {
                kind = .key
                key = Self.keyDescription(event: event, characters: characters)
            }
        default:
            return nil
        }
    }

    private static func isPrintable(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        return text.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }

    private static func keyDescription(event: NSEvent, characters: String) -> String {
        var parts: [String] = []
        let modifiers = event.modifierFlags
        if modifiers.contains(.command) { parts.append("Command") }
        if modifiers.contains(.control) { parts.append("Control") }
        if modifiers.contains(.option) { parts.append("Option") }
        if modifiers.contains(.shift) { parts.append("Shift") }
        parts.append(Self.namedKey(event.keyCode) ?? characters.uppercased().nonEmpty ?? "Key")
        return parts.joined(separator: "+")
    }

    private static func namedKey(_ keyCode: UInt16) -> String? {
        switch keyCode {
        case 36: return "Return"
        case 48: return "Tab"
        case 49: return "Space"
        case 51: return "Delete"
        case 53: return "Escape"
        case 123: return "Left Arrow"
        case 124: return "Right Arrow"
        case 125: return "Down Arrow"
        case 126: return "Up Arrow"
        default: return nil
        }
    }

    private static func focusedElementIsProtected() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        guard let focused: AXUIElement = attribute(kAXFocusedUIElementAttribute, from: systemWide) else {
            return false
        }
        if let protected = attribute("AXProtectedContent", from: focused) as NSNumber?,
           protected.boolValue {
            return true
        }
        let subrole: String? = attribute(kAXSubroleAttribute, from: focused)
        return subrole == "AXSecureTextField"
    }

    private static func attribute<T>(_ name: String, from element: AXUIElement) -> T? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        guard error == .success else { return nil }
        return value as? T
    }
}

@MainActor
private final class MacWorkflowEventMonitors: @unchecked Sendable {
    private var globalMonitor: Any?
    private var localMonitor: Any?

    init(handler: @escaping @Sendable (MacWorkflowInput) -> Void) {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .scrollWheel, .keyDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { event in
            guard let input = MacWorkflowInput(event: event) else { return }
            handler(input)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            if let input = MacWorkflowInput(event: event) {
                handler(input)
            }
            return event
        }
    }

    func invalidate() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
#endif
