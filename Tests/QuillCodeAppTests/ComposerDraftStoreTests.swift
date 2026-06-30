import XCTest
@testable import QuillCodeApp

final class ComposerDraftStoreTests: XCTestCase {
    func testSaveOutgoingAndRestoreIncomingRoundTrip() {
        let a = UUID()
        let b = UUID()

        // Type in A, switch to B: A's draft is stashed, B restores empty.
        let toB = ComposerDraftStore.select(outgoing: a, incoming: b, liveDraft: "draft A", drafts: [:])
        XCTAssertEqual(toB.restoredDraft, "")
        XCTAssertEqual(toB.drafts[a], "draft A")

        // Type in B, switch back to A: B's draft is stashed, A's draft restored.
        let toA = ComposerDraftStore.select(outgoing: b, incoming: a, liveDraft: "draft B", drafts: toB.drafts)
        XCTAssertEqual(toA.restoredDraft, "draft A")
        XCTAssertEqual(toA.drafts[b], "draft B")
        // The restored thread's entry is consumed.
        XCTAssertNil(toA.drafts[a])
    }

    func testEmptyOrWhitespaceDraftIsNotStored() {
        let a = UUID()
        let b = UUID()
        let blank = ComposerDraftStore.select(outgoing: a, incoming: b, liveDraft: "   \n ", drafts: [a: "stale"])
        XCTAssertNil(blank.drafts[a])
        XCTAssertEqual(blank.restoredDraft, "")
    }

    func testSameThreadSelectionIsNoOp() {
        let a = UUID()
        let result = ComposerDraftStore.select(outgoing: a, incoming: a, liveDraft: "in progress", drafts: [:])
        XCTAssertEqual(result.restoredDraft, "in progress")
        XCTAssertTrue(result.drafts.isEmpty)
    }

    func testUnknownIncomingThreadRestoresEmpty() {
        let a = UUID()
        let b = UUID()
        let result = ComposerDraftStore.select(outgoing: a, incoming: b, liveDraft: "draft A", drafts: [:])
        XCTAssertEqual(result.restoredDraft, "")
    }

    func testNilOutgoingDoesNotStashButStillRestores() {
        let b = UUID()
        let result = ComposerDraftStore.select(outgoing: nil, incoming: b, liveDraft: "ignored", drafts: [b: "draft B"])
        XCTAssertEqual(result.restoredDraft, "draft B")
        XCTAssertNil(result.drafts[b])
    }

    func testClearedDropsThreadDraft() {
        let a = UUID()
        let b = UUID()
        let drafts = [a: "draft A", b: "draft B"]
        XCTAssertNil(ComposerDraftStore.cleared(a, drafts: drafts)[a])
        XCTAssertEqual(ComposerDraftStore.cleared(a, drafts: drafts)[b], "draft B")
        XCTAssertEqual(ComposerDraftStore.cleared(nil, drafts: drafts), drafts)
    }
}
