import XCTest

final class ParitySafetyGateTests: QuillCodeParityTestCase {
    func testStaticSafetyPolicyLivesOutsideReviewerControlFlow() throws {
        let reviewerText = try Self.safetySourceText(named: "Safety.swift")
        let policyText = try Self.safetySourceText(named: "StaticSafetyPolicy.swift")

        XCTAssertTrue(policyText.contains("struct StaticSafetyPolicy"), "Static safety intent policy should live in a focused policy file.")
        XCTAssertTrue(policyText.contains("StaticSafetyHardDenyRule"), "Hard-deny patterns should be explicit policy table entries.")
        XCTAssertTrue(policyText.contains("StaticSafetyIntentRule"), "Intent-to-tool matching should use table-driven rules.")
        XCTAssertTrue(policyText.contains("StaticSafetyPullRequestPolicy"), "Pull request safety routing should live beside the static policy tables.")
        XCTAssertTrue(reviewerText.contains("policy.hardDenyReason"), "StaticSafetyReviewer should delegate hard-deny checks to the policy.")
        XCTAssertTrue(reviewerText.contains("policy.userIntentMatches"), "StaticSafetyReviewer should delegate intent matching to the policy.")
        XCTAssertFalse(reviewerText.contains(#""rm -rf /""#), "StaticSafetyReviewer should not own raw hard-deny command patterns.")
        XCTAssertFalse(reviewerText.contains("user.contains(\"pull request\")"), "StaticSafetyReviewer should not own raw pull-request intent chains.")
    }
}
