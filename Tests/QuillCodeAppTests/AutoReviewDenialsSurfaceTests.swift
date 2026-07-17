import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence
import QuillCodeSafety
import QuillCodeTools
@testable import QuillCodeApp

@MainActor
final class AutoReviewDenialsSurfaceTests: XCTestCase {
    func testSurfacePresentsDurableDenialMetadataAndEscapedHTML() throws {
        let workspaceRoot = try makeTempDirectory()
        let project = ProjectRef(name: "QuillCode", path: workspaceRoot.path)
        var thread = ChatThread(
            projectID: project.id,
            mode: .auto,
            messages: [.init(role: .user, content: "Run whoami", turnID: "turn-1")]
        )
        let request = makeDeniedRequest(
            id: "approval-<unsafe>",
            call: ToolCall(
                name: ToolDefinition.shellRun.name,
                argumentsJSON: ToolArguments.json(["cmd": "whoami"])
            ),
            thread: thread,
            workspaceRoot: workspaceRoot
        )
        thread.events.append(contentsOf: try denialEvents(
            request: request,
            reason: "The task needs <explicit> confirmation."
        ))

        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [project],
            selectedProjectID: project.id,
            threads: [thread],
            selectedThreadID: thread.id
        ))

        XCTAssertTrue(model.runWorkspaceCommand("auto-review-denials", workspaceRoot: workspaceRoot))
        let surface = try XCTUnwrap(model.surface().autoReviewDenials)
        let item = try XCTUnwrap(surface.items.first)
        XCTAssertEqual(item.requestID, request.id)
        XCTAssertEqual(item.toolName, "Shell command")
        XCTAssertTrue(item.actionSummary.contains("whoami"))
        XCTAssertEqual(item.reason, "The task needs <explicit> confirmation.")
        XCTAssertEqual(item.riskLabel, "Medium")
        XCTAssertEqual(item.authorizationLabel, "Explicit request")
        XCTAssertEqual(item.retryState, .available)
        XCTAssertEqual(
            item.retryCommandID,
            WorkspaceCommandPlan.autoReviewDenialRetryCommandID(request.id)
        )

        let html = WorkspaceHTMLRenderer.render(model.surface())
        XCTAssertTrue(html.contains(#"data-testid="auto-review-denials-dialog""#))
        XCTAssertTrue(html.contains(#"data-testid="auto-review-denial-retry""#))
        XCTAssertTrue(html.contains("approval-&lt;unsafe&gt;"))
        XCTAssertTrue(html.contains("The task needs &lt;explicit&gt; confirmation."))
        XCTAssertFalse(html.contains("The task needs <explicit> confirmation."))

        XCTAssertTrue(model.runWorkspaceCommand("auto-review-denials-dismiss", workspaceRoot: workspaceRoot))
        XCTAssertNil(model.surface().autoReviewDenials)
    }

    func testSurfaceExplainsUnavailableConsumedAndChangedContextRetries() throws {
        let workspaceRoot = try makeTempDirectory()
        var thread = ChatThread(
            mode: .auto,
            messages: [.init(role: .user, content: "Run the checks", turnID: "turn-1")]
        )

        let privateCall = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "env", "env": ["TOKEN": "secret"]])
        )
        let privateRequest = makeDeniedRequest(
            id: "approval-private",
            call: privateCall,
            presentedCall: privateCall.redactedForTranscript(),
            thread: thread,
            workspaceRoot: workspaceRoot
        )
        thread.events.append(contentsOf: try denialEvents(request: privateRequest))

        let consumedCall = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "whoami"])
        )
        let consumedRequest = makeDeniedRequest(
            id: "approval-consumed",
            call: consumedCall,
            thread: thread,
            workspaceRoot: workspaceRoot
        )
        thread.events.append(contentsOf: try denialEvents(request: consumedRequest))
        let retry = ApprovalRequest(
            id: "approval-consumed-retry",
            toolCall: consumedCall,
            toolDefinition: ToolDefinition.shellRun,
            reason: "Exact retry",
            reviewAttempt: .denialOverride(requestID: consumedRequest.id)
        )
        thread.events.append(try approvalRequestEvent(retry))

        let changedRequest = makeDeniedRequest(
            id: "approval-context",
            call: consumedCall,
            thread: thread,
            workspaceRoot: workspaceRoot
        )
        thread.events.append(contentsOf: try denialEvents(request: changedRequest))
        thread.messages.append(.init(role: .user, content: "A different task", turnID: "turn-2"))

        let items = AutoReviewDenialsSurfaceBuilder.surface(
            thread: thread,
            workspaceRoot: workspaceRoot,
            retryingRequestID: nil
        ).items
        XCTAssertEqual(items.first(where: { $0.id == privateRequest.id })?.retryState, .unavailable)
        XCTAssertEqual(items.first(where: { $0.id == consumedRequest.id })?.retryState, .consumed)
        XCTAssertEqual(items.first(where: { $0.id == changedRequest.id })?.retryState, .contextChanged)
        XCTAssertTrue(items.allSatisfy { $0.canRetry == ($0.retryState == .available) })
    }

    func testExactRetryExecutesOnceAndPersistsConsumedState() async throws {
        let workspaceRoot = try makeTempDirectory()
        let store = JSONThreadStore(directory: workspaceRoot.appendingPathComponent("threads"))
        let project = ProjectRef(name: "QuillCode", path: workspaceRoot.path)
        var thread = ChatThread(
            projectID: project.id,
            mode: .auto,
            messages: [.init(role: .user, content: "Create approved.txt", turnID: "turn-1")]
        )
        let call = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json(["path": "approved.txt", "content": "done"])
        )
        let request = makeDeniedRequest(
            id: "approval-persisted",
            call: call,
            thread: thread,
            workspaceRoot: workspaceRoot
        )
        thread.events.append(contentsOf: try denialEvents(request: request))
        try store.save(thread)

        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                projects: [project],
                selectedProjectID: project.id,
                threads: [thread],
                selectedThreadID: thread.id
            ),
            runner: AgentRunner(safety: ApprovingRetrySafetyReviewer()),
            threadStore: store
        )

        await model.retryAutoReviewDenial(requestID: request.id, workspaceRoot: workspaceRoot)

        XCTAssertNil(model.lastError)
        XCTAssertEqual(
            try String(contentsOf: workspaceRoot.appendingPathComponent("approved.txt"), encoding: .utf8),
            "done"
        )
        let persisted = try store.load(thread.id)
        XCTAssertEqual(
            AutoReviewDenialHistory.records(in: persisted, workspaceRoot: workspaceRoot).first?.retryState,
            .consumed
        )
        let retryRequests = persisted.events.compactMap { event -> ApprovalRequest? in
            guard event.kind == .approvalRequested, let payload = event.payloadJSON else { return nil }
            return try? JSONHelpers.decode(ApprovalRequest.self, from: payload)
        }.filter { $0.reviewAttempt == .denialOverride(requestID: request.id) }
        XCTAssertEqual(retryRequests.count, 1)

        await model.retryAutoReviewDenial(requestID: request.id, workspaceRoot: workspaceRoot)
        XCTAssertEqual(model.lastError, AgentAutoReviewRetryError.retryConsumed.localizedDescription)
        XCTAssertEqual(
            try JSONThreadStore(directory: store.directory).load(thread.id).events.count,
            persisted.events.count
        )
    }

    private func makeDeniedRequest(
        id: String,
        call: ToolCall,
        presentedCall: ToolCall? = nil,
        thread: ChatThread,
        workspaceRoot: URL
    ) -> ApprovalRequest {
        let presentedCall = presentedCall ?? call
        let telemetry = ApprovalReviewTelemetry(
            source: .primaryModel,
            reviewerModel: "glm-5.2",
            attemptedModels: ["glm-5.2"],
            riskLevel: .medium,
            userAuthorization: .explicit
        )
        return ApprovalRequest(
            id: id,
            toolCall: presentedCall,
            toolDefinition: nil,
            reason: "Denied",
            recommendedVerdict: .deny,
            reviewTelemetry: telemetry,
            actionIdentity: .make(
                executableCall: call,
                presentedCall: presentedCall,
                thread: thread,
                workspaceRoot: workspaceRoot
            )
        )
    }

    private func denialEvents(
        request: ApprovalRequest,
        reason: String = "The action was denied."
    ) throws -> [ThreadEvent] {
        let decision = ApprovalDecision(
            requestID: request.id,
            verdict: .deny,
            rationale: reason,
            reviewTelemetry: request.reviewTelemetry,
            reviewOutcome: .denied
        )
        return [
            try approvalRequestEvent(request),
            ThreadEvent(
                kind: .approvalDecided,
                summary: "Denied",
                payloadJSON: try JSONHelpers.encodePretty(decision)
            )
        ]
    }

    private func approvalRequestEvent(_ request: ApprovalRequest) throws -> ThreadEvent {
        ThreadEvent(
            kind: .approvalRequested,
            summary: "Review requested",
            payloadJSON: try JSONHelpers.encodePretty(request)
        )
    }
}

private struct ApprovingRetrySafetyReviewer: SafetyReviewer {
    func review(_ context: SafetyContext) async -> SafetyReview {
        SafetyReview(
            verdict: .approve,
            rationale: context.reviewAttempt.kind == .denialOverride
                ? "The exact retry is approved."
                : "Approved."
        )
    }
}
