import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceSubagentApprovalPayloadResolverTests: XCTestCase {
    func testToolApprovalRequiresExactHeldCallIdentityAndName() throws {
        let presented = ToolCall(id: "call-1", name: "host.shell.run", argumentsJSON: #"{"cmd":"<redacted>"}"#)
        let request = ApprovalRequest(
            toolCall: presented,
            toolDefinition: nil,
            reason: "Approval required"
        )
        let held = ToolCall(id: "call-1", name: "host.shell.run", argumentsJSON: #"{"cmd":"whoami"}"#)

        XCTAssertEqual(
            try WorkspaceSubagentApprovalPayloadResolver.payload(for: request, heldToolCall: held),
            held
        )
        XCTAssertThrowsError(try WorkspaceSubagentApprovalPayloadResolver.payload(
            for: request,
            heldToolCall: ToolCall(id: "call-2", name: held.name, argumentsJSON: held.argumentsJSON)
        ))
        XCTAssertThrowsError(try WorkspaceSubagentApprovalPayloadResolver.payload(
            for: request,
            heldToolCall: nil
        ))
    }

    func testSpendFuseUsesItsPersistedSyntheticCall() throws {
        let call = ToolCall(id: "spend-1", name: "host.run.spend-fuse", argumentsJSON: "{}")
        let request = ApprovalRequest(
            scope: .runSpendFuse,
            toolCall: call,
            toolDefinition: nil,
            reason: "Spend limit reached"
        )

        XCTAssertEqual(
            try WorkspaceSubagentApprovalPayloadResolver.payload(for: request, heldToolCall: nil),
            call
        )
    }
}
