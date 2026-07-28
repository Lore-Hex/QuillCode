import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeAgent

final class MockLLMClientMultiFileArtifactTests: XCTestCase {
    func testTeamActionBriefStartsByReadingResearchFile() async throws {
        let action = try await MockLLMClient().nextAction(
            thread: ChatThread(mode: .auto),
            userMessage: "Create the team action brief from `notes/research.md` and `notes/risks.md`.",
            tools: ToolRouter.definitions
        )

        let call = try XCTUnwrap(action.toolCall)
        XCTAssertEqual(call.name, ToolDefinition.fileRead.name)
        XCTAssertEqual(try ToolArguments(call.argumentsJSON).string("path"), "notes/research.md")
    }

    func testTeamActionBriefContinuesThroughSecondReadAndWrite() async throws {
        let user = ChatMessage(
            role: .user,
            content: "Create the team action brief from `notes/research.md` and `notes/risks.md`."
        )
        let researchRead = ToolCall(
            name: ToolDefinition.fileRead.name,
            argumentsJSON: ToolArguments.json(["path": "notes/research.md"])
        )
        let afterResearch = ChatThread(
            mode: .auto,
            messages: [
                user,
                try toolFeedbackMessage(
                    for: researchRead,
                    stdout: "Customers asked for QuillCloud relay reliability."
                )
            ]
        )

        let secondAction = try await MockLLMClient().nextAction(
            thread: afterResearch,
            userMessage: user.content,
            tools: ToolRouter.definitions
        )
        let secondCall = try XCTUnwrap(secondAction.toolCall)
        XCTAssertEqual(secondCall.name, ToolDefinition.fileRead.name)
        XCTAssertEqual(try ToolArguments(secondCall.argumentsJSON).string("path"), "notes/risks.md")

        let risksRead = ToolCall(
            name: ToolDefinition.fileRead.name,
            argumentsJSON: ToolArguments.json(["path": "notes/risks.md"])
        )
        let afterRisks = ChatThread(
            mode: .auto,
            messages: [
                user,
                try toolFeedbackMessage(
                    for: researchRead,
                    stdout: "Customers asked for QuillCloud relay reliability."
                ),
                try toolFeedbackMessage(for: risksRead, stdout: "The top risk is pairing fallback.")
            ]
        )

        let writeAction = try await MockLLMClient().nextAction(
            thread: afterRisks,
            userMessage: user.content,
            tools: ToolRouter.definitions
        )
        let writeCall = try XCTUnwrap(writeAction.toolCall)
        XCTAssertEqual(writeCall.name, ToolDefinition.fileWrite.name)
        let writeArguments = try ToolArguments(writeCall.argumentsJSON)
        XCTAssertEqual(writeArguments.string("path"), "team-action-brief.md")
        XCTAssertTrue(writeArguments.string("content")?.contains("QuillCloud relay reliability") == true)
        XCTAssertTrue(writeArguments.string("content")?.contains("pairing fallback") == true)

        let writeFeedback = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json(["path": "team-action-brief.md"])
        )
        let afterWrite = ChatThread(
            mode: .auto,
            messages: [
                user,
                try toolFeedbackMessage(for: writeFeedback, stdout: "wrote team-action-brief.md")
            ]
        )
        let finalAction = try await MockLLMClient().nextAction(
            thread: afterWrite,
            userMessage: user.content,
            tools: ToolRouter.definitions
        )
        guard case .say(let finalAnswer) = finalAction else {
            return XCTFail("Expected a final answer after the write completes.")
        }
        XCTAssertEqual(
            finalAnswer,
            "Created `team-action-brief.md` from `notes/research.md` and `notes/risks.md`."
        )
    }

    func testAllHandsEmailStartsByReadingOrgChangesDeck() async throws {
        let action = try await MockLLMClient().nextAction(
            thread: ChatThread(mode: .auto),
            userMessage: "Draft the CEO all-hands email announcing the reorg from `org-changes.pptx` and the answers in `reorg-qa`, covering the eight hardest questions.",
            tools: ToolRouter.definitions
        )

        let call = try XCTUnwrap(action.toolCall)
        XCTAssertEqual(call.name, ToolDefinition.fileRead.name)
        XCTAssertEqual(try ToolArguments(call.argumentsJSON).string("path"), "org-changes.pptx")
    }

    func testAllHandsEmailReadsQANotesThenWritesDraft() async throws {
        let user = ChatMessage(
            role: .user,
            content: "Draft the CEO all-hands email announcing the reorg from `org-changes.pptx` and the answers in `reorg-qa`, covering the eight hardest questions."
        )
        let orgRead = ToolCall(
            name: ToolDefinition.fileRead.name,
            argumentsJSON: ToolArguments.json(["path": "org-changes.pptx"])
        )
        let afterOrgRead = ChatThread(
            mode: .auto,
            messages: [
                user,
                try toolFeedbackMessage(
                    for: orgRead,
                    stdout: "Product Operations moves under Engineering."
                )
            ]
        )

        let qaAction = try await MockLLMClient().nextAction(
            thread: afterOrgRead,
            userMessage: user.content,
            tools: ToolRouter.definitions
        )
        let qaCall = try XCTUnwrap(qaAction.toolCall)
        XCTAssertEqual(qaCall.name, ToolDefinition.fileRead.name)
        XCTAssertEqual(try ToolArguments(qaCall.argumentsJSON).string("path"), "reorg-qa/hardest-questions.md")

        let qaRead = ToolCall(
            name: ToolDefinition.fileRead.name,
            argumentsJSON: ToolArguments.json(["path": "reorg-qa/hardest-questions.md"])
        )
        let afterQARead = ChatThread(
            mode: .auto,
            messages: [
                user,
                try toolFeedbackMessage(for: orgRead, stdout: "Product Operations moves under Engineering."),
                try toolFeedbackMessage(for: qaRead, stdout: "1. Why now? 2. Are there layoffs?")
            ]
        )

        let writeAction = try await MockLLMClient().nextAction(
            thread: afterQARead,
            userMessage: user.content,
            tools: ToolRouter.definitions
        )
        let writeCall = try XCTUnwrap(writeAction.toolCall)
        XCTAssertEqual(writeCall.name, ToolDefinition.fileWrite.name)
        let writeArguments = try ToolArguments(writeCall.argumentsJSON)
        XCTAssertEqual(writeArguments.string("path"), "ceo-reorg-all-hands-email.md")
        XCTAssertTrue(writeArguments.string("content")?.contains("Product Operations moves under Engineering") == true)
        XCTAssertTrue(writeArguments.string("content")?.contains("8. Where do questions go?") == true)

        let writeFeedback = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json(["path": "ceo-reorg-all-hands-email.md"])
        )
        let afterWrite = ChatThread(
            mode: .auto,
            messages: [
                user,
                try toolFeedbackMessage(for: writeFeedback, stdout: "wrote ceo-reorg-all-hands-email.md")
            ]
        )
        let finalAction = try await MockLLMClient().nextAction(
            thread: afterWrite,
            userMessage: user.content,
            tools: ToolRouter.definitions
        )
        guard case .say(let finalAnswer) = finalAction else {
            return XCTFail("Expected a final answer after the all-hands email write completes.")
        }
        XCTAssertEqual(
            finalAnswer,
            "Created `ceo-reorg-all-hands-email.md` from `org-changes.pptx` and `reorg-qa/hardest-questions.md`."
        )
    }

    func testAnalystSynthesisStartsByReadingFirstAnalystReport() async throws {
        let action = try await MockLLMClient().nextAction(
            thread: ChatThread(mode: .auto),
            userMessage: "Pull the key claims from the three Gartner and Forrester PDFs in `analyst-reports` and flag where they contradict each other.",
            tools: ToolRouter.definitions
        )

        let call = try XCTUnwrap(action.toolCall)
        XCTAssertEqual(call.name, ToolDefinition.fileRead.name)
        XCTAssertEqual(try ToolArguments(call.argumentsJSON).string("path"), "analyst-reports/gartner-market-guide.pdf")
    }

    func testAnalystSynthesisReadsAllReportsThenWritesContradictions() async throws {
        let user = ChatMessage(
            role: .user,
            content: "Pull the key claims from the three Gartner and Forrester PDFs in `analyst-reports` and flag where they contradict each other."
        )
        let gartnerRead = ToolCall(
            name: ToolDefinition.fileRead.name,
            argumentsJSON: ToolArguments.json(["path": "analyst-reports/gartner-market-guide.pdf"])
        )
        let afterGartnerRead = ChatThread(
            mode: .auto,
            messages: [
                user,
                try toolFeedbackMessage(for: gartnerRead, stdout: "Gartner says governance depth matters.")
            ]
        )

        let forresterWaveAction = try await MockLLMClient().nextAction(
            thread: afterGartnerRead,
            userMessage: user.content,
            tools: ToolRouter.definitions
        )
        let forresterWaveCall = try XCTUnwrap(forresterWaveAction.toolCall)
        XCTAssertEqual(forresterWaveCall.name, ToolDefinition.fileRead.name)
        XCTAssertEqual(
            try ToolArguments(forresterWaveCall.argumentsJSON).string("path"),
            "analyst-reports/forrester-wave.pdf"
        )

        let forresterWaveRead = ToolCall(
            name: ToolDefinition.fileRead.name,
            argumentsJSON: ToolArguments.json(["path": "analyst-reports/forrester-wave.pdf"])
        )
        let afterWaveRead = ChatThread(
            mode: .auto,
            messages: [
                user,
                try toolFeedbackMessage(for: gartnerRead, stdout: "Gartner says governance depth matters."),
                try toolFeedbackMessage(for: forresterWaveRead, stdout: "Forrester says fast time-to-value matters.")
            ]
        )

        let nowTechAction = try await MockLLMClient().nextAction(
            thread: afterWaveRead,
            userMessage: user.content,
            tools: ToolRouter.definitions
        )
        let nowTechCall = try XCTUnwrap(nowTechAction.toolCall)
        XCTAssertEqual(nowTechCall.name, ToolDefinition.fileRead.name)
        XCTAssertEqual(
            try ToolArguments(nowTechCall.argumentsJSON).string("path"),
            "analyst-reports/forrester-now-tech.pdf"
        )

        let nowTechRead = ToolCall(
            name: ToolDefinition.fileRead.name,
            argumentsJSON: ToolArguments.json(["path": "analyst-reports/forrester-now-tech.pdf"])
        )
        let afterNowTechRead = ChatThread(
            mode: .auto,
            messages: [
                user,
                try toolFeedbackMessage(for: gartnerRead, stdout: "Gartner says governance depth matters."),
                try toolFeedbackMessage(for: forresterWaveRead, stdout: "Forrester says fast time-to-value matters."),
                try toolFeedbackMessage(for: nowTechRead, stdout: "Forrester says extensibility matters.")
            ]
        )

        let writeAction = try await MockLLMClient().nextAction(
            thread: afterNowTechRead,
            userMessage: user.content,
            tools: ToolRouter.definitions
        )
        let writeCall = try XCTUnwrap(writeAction.toolCall)
        XCTAssertEqual(writeCall.name, ToolDefinition.fileWrite.name)
        let writeArguments = try ToolArguments(writeCall.argumentsJSON)
        XCTAssertEqual(writeArguments.string("path"), "analyst-claims-contradictions.md")
        XCTAssertTrue(writeArguments.string("content")?.contains("Gartner says") == true)
        XCTAssertTrue(writeArguments.string("content")?.contains("Contradictions") == true)

        let writeFeedback = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json(["path": "analyst-claims-contradictions.md"])
        )
        let afterWrite = ChatThread(
            mode: .auto,
            messages: [
                user,
                try toolFeedbackMessage(for: writeFeedback, stdout: "wrote analyst-claims-contradictions.md")
            ]
        )
        let finalAction = try await MockLLMClient().nextAction(
            thread: afterWrite,
            userMessage: user.content,
            tools: ToolRouter.definitions
        )
        guard case .say(let finalAnswer) = finalAction else {
            return XCTFail("Expected a final answer after the analyst synthesis write completes.")
        }
        XCTAssertEqual(
            finalAnswer,
            "Created `analyst-claims-contradictions.md` from the three reports in `analyst-reports`."
        )
    }

    func testBulkInvoiceRenameStartsByReadingFirstInvoice() async throws {
        let action = try await MockLLMClient().nextAction(
            thread: ChatThread(mode: .auto),
            userMessage: "Rename every PDF in `Documents/Invoices` to YYYY-MM-DD_Vendor_Amount.pdf based on what's inside each file, and leave an undo log.",
            tools: ToolRouter.definitions
        )

        let call = try XCTUnwrap(action.toolCall)
        XCTAssertEqual(call.name, ToolDefinition.fileRead.name)
        XCTAssertEqual(try ToolArguments(call.argumentsJSON).string("path"), "Documents/Invoices/invoice-acme.pdf")
    }

    func testBulkInvoiceRenameReadsInvoicesThenRunsRenameCommand() async throws {
        let user = ChatMessage(
            role: .user,
            content: "Rename every PDF in `Documents/Invoices` to YYYY-MM-DD_Vendor_Amount.pdf based on what's inside each file, and leave an undo log."
        )
        let acmeRead = ToolCall(
            name: ToolDefinition.fileRead.name,
            argumentsJSON: ToolArguments.json(["path": "Documents/Invoices/invoice-acme.pdf"])
        )
        let afterAcmeRead = ChatThread(
            mode: .auto,
            messages: [
                user,
                try toolFeedbackMessage(for: acmeRead, stdout: "Invoice date 2026-07-03 vendor Acme amount 1542.10")
            ]
        )

        let northwindAction = try await MockLLMClient().nextAction(
            thread: afterAcmeRead,
            userMessage: user.content,
            tools: ToolRouter.definitions
        )
        let northwindCall = try XCTUnwrap(northwindAction.toolCall)
        XCTAssertEqual(northwindCall.name, ToolDefinition.fileRead.name)
        XCTAssertEqual(
            try ToolArguments(northwindCall.argumentsJSON).string("path"),
            "Documents/Invoices/invoice-northwind.pdf"
        )

        let northwindRead = ToolCall(
            name: ToolDefinition.fileRead.name,
            argumentsJSON: ToolArguments.json(["path": "Documents/Invoices/invoice-northwind.pdf"])
        )
        let afterNorthwindRead = ChatThread(
            mode: .auto,
            messages: [
                user,
                try toolFeedbackMessage(for: acmeRead, stdout: "Invoice date 2026-07-03 vendor Acme amount 1542.10"),
                try toolFeedbackMessage(for: northwindRead, stdout: "Invoice date 2026-07-09 vendor Northwind amount 880.00")
            ]
        )

        let renameAction = try await MockLLMClient().nextAction(
            thread: afterNorthwindRead,
            userMessage: user.content,
            tools: ToolRouter.definitions
        )
        let renameCall = try XCTUnwrap(renameAction.toolCall)
        XCTAssertEqual(renameCall.name, ToolDefinition.shellRun.name)
        let command = try XCTUnwrap(ToolArguments(renameCall.argumentsJSON).string("cmd"))
        XCTAssertTrue(command.contains("2026-07-03_Acme_1542.10.pdf"))
        XCTAssertTrue(command.contains("2026-07-09_Northwind_880.00.pdf"))
        XCTAssertTrue(command.contains("invoice-rename-undo.csv"))

        let renameFeedback = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": command])
        )
        let afterRename = ChatThread(
            mode: .auto,
            messages: [
                user,
                try toolFeedbackMessage(for: renameFeedback, stdout: "renamed 2 invoices")
            ]
        )
        let finalAction = try await MockLLMClient().nextAction(
            thread: afterRename,
            userMessage: user.content,
            tools: ToolRouter.definitions
        )
        guard case .say(let finalAnswer) = finalAction else {
            return XCTFail("Expected a final answer after the invoice rename completes.")
        }
        XCTAssertEqual(
            finalAnswer,
            "Renamed invoice PDFs in `Documents/Invoices` and wrote `Documents/Invoices/invoice-rename-undo.csv`."
        )
    }

    private func toolFeedbackMessage(for call: ToolCall, stdout: String) throws -> ChatMessage {
        let feedback = AgentToolFeedback(
            toolCall: call,
            result: ToolResult(ok: true, stdout: stdout)
        )
        return ChatMessage(role: .tool, content: try JSONHelpers.encodePretty(feedback))
    }
}

private extension AgentAction {
    var toolCall: ToolCall? {
        guard case .tool(let call) = self else { return nil }
        return call
    }
}
