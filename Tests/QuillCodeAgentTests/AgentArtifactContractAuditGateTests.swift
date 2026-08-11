import XCTest
import QuillCodeCore
@testable import QuillCodeAgent

final class AgentArtifactContractAuditGateTests: XCTestCase {
    func testRejectsUnavailableArtifactWhenStructuredEvidenceContainsValues() throws {
        let evidence = """
        Year | Jan | Feb | Mar
        2025 | 317.671 | 319.082 | 324.054
        2026 | 325.252 | 326.785 | 333.952
        """
        let artifact = """
        # Report

        The numeric value cells were truncated. No CPI index could be confirmed, so I cannot
        compute the requested restatement.
        """

        let issue = try XCTUnwrap(AgentArtifactContractAuditGate.evidenceContradiction(
            artifact: artifact,
            evidenceReceipt: evidence
        ))
        XCTAssertTrue(issue.contains("numeric observations"))
        XCTAssertTrue(issue.contains("requested calculations"))
    }

    func testAllowsUnavailableDisclosureWhenReceiptHasNoStructuredValues() {
        XCTAssertNil(AgentArtifactContractAuditGate.evidenceContradiction(
            artifact: "The source was unavailable, so I cannot compute the result.",
            evidenceReceipt: "HTTP Status 404 - Not Found"
        ))
    }

    func testAllowsArtifactThatUsesRetainedStructuredEvidence() {
        let evidence = """
        Year | Jan | Feb | Mar
        2025 | 317.671 | 319.082 | 324.054
        2026 | 325.252 | 326.785 | 333.952
        """
        let artifact = """
        The bulk endpoint was unavailable, but the official table supplied 333.952 as the latest
        monthly benchmark, so the requested calculation was completed.
        """
        XCTAssertNil(AgentArtifactContractAuditGate.evidenceContradiction(
            artifact: artifact,
            evidenceReceipt: evidence
        ))
    }

    func testRejectsLatestPeriodClaimPairedWithAdjacentSourceValue() throws {
        let evidence = """
        | Year | Jan | Feb | Mar | Apr | May | Jun | Jul | HALF1 |
        | --- | --- | --- | --- | --- | --- | --- | --- | --- |
        | 2026 | 325.252 | 326.785 | 330.213 | 333.020 | 335.123 | 333.952 | | 330.724 |
        """
        let artifact = """
        The latest published monthly benchmark is June 2026, index 326.785.
        """

        let issue = try XCTUnwrap(AgentArtifactContractAuditGate.evidenceContradiction(
            artifact: artifact,
            evidenceReceipt: evidence
        ))
        XCTAssertTrue(issue.contains("Jun 2026"))
        XCTAssertTrue(issue.contains("326.785"))
        XCTAssertTrue(issue.contains("333.952"))
    }

    func testRejectsLatestPeriodTableRowWithValueBeforeLabel() throws {
        let evidence = """
        | Year | Jan | Feb | Mar | Apr | May | Jun | HALF1 |
        | --- | --- | --- | --- | --- | --- | --- | --- |
        | 2026 | 325.252 | 326.785 | 330.213 | 333.020 | 335.123 | 333.952 | 330.724 |
        """
        let artifact = """
        | Year | CPI basis | Type |
        | --- | --- | --- |
        | 2026 | **325.252** | latest published monthly index - January 2026 benchmark |
        """

        let issue = try XCTUnwrap(AgentArtifactContractAuditGate.evidenceContradiction(
            artifact: artifact,
            evidenceReceipt: evidence
        ))
        XCTAssertTrue(issue.contains("jan 2026 at 325.252"), issue)
        XCTAssertTrue(issue.contains("Jun 2026 at 333.952"), issue)
    }

    func testRejectsLatestPeriodClaimOnTask126MultiValueRow() throws {
        let evidence = """
        | Year | Jan | Feb | Mar | Apr | May | Jun | Jul | Aug | Sep | Oct | Nov | Dec | HALF1 | HALF2 |
        | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
        | 2026 | 325.252 | 326.785 | 330.213 | 333.020 | 335.123 | 333.952 | | | | | | | 330.724 | |
        """
        let artifact = """
        | Year | CPI basis selected | Value | Note |
        | --- | --- | --- | --- |
        | 2026 (target) | Latest published monthly index = **July 2026** | 333.952 | No full-year 2026 CPI value exists; Jan-Jun are published. |
        """

        let issue = try XCTUnwrap(AgentArtifactContractAuditGate.evidenceContradiction(
            artifact: artifact,
            evidenceReceipt: evidence
        ))
        XCTAssertTrue(issue.contains("jul 2026 at 333.952"), issue)
        XCTAssertTrue(issue.contains("Jun 2026 at 333.952"), issue)
    }

    func testAllowsLatestPeriodClaimPairedBySourceHeader() {
        let evidence = """
        | Year | Jan | Feb | Mar | Apr | May | Jun | Jul | HALF1 |
        | --- | --- | --- | --- | --- | --- | --- | --- | --- |
        | 2026 | 325.252 | 326.785 | 330.213 | 333.020 | 335.123 | 333.952 | | 330.724 |
        """
        let artifact = "The latest published monthly benchmark is June 2026, index 333.952."

        XCTAssertNil(AgentArtifactContractAuditGate.evidenceContradiction(
            artifact: artifact,
            evidenceReceipt: evidence
        ))
    }

    func testRejectsLatestMonthlyBenchmarkRelabeledAsHalfYearMean() throws {
        let evidence = """
        | Year | Jan | Feb | Mar | Apr | May | Jun | HALF1 |
        | --- | --- | --- | --- | --- | --- | --- | --- |
        | 2026 | 325.252 | 326.785 | 330.213 | 333.020 | 335.123 | 333.952 | 330.724 |
        """
        let artifact = """
        | Fiscal year | Basis type | Selected basis index | Observation basis |
        | --- | --- | --- | --- |
        | 2026 | Monthly benchmark | 330.724167 | Arithmetic mean of Jan-Jun published indexes |
        """

        let issue = try XCTUnwrap(AgentArtifactContractAuditGate.evidenceContradiction(
            artifact: artifact,
            evidenceReceipt: evidence
        ))
        XCTAssertTrue(issue.contains("Jun 2026"), issue)
        XCTAssertTrue(issue.contains("330.724167"), issue)
        XCTAssertTrue(issue.contains("333.952"), issue)
    }

    func testAllowsUnrelatedMetricFromSameMonthAndYear() {
        let evidence = """
        | Year | May | Jun | HALF1 |
        | --- | --- | --- | --- |
        | 2026 | 335.123 | 333.952 | 334.538 |
        """
        let artifact = "The company reported June 2026 revenue of 326.785 million."

        XCTAssertNil(AgentArtifactContractAuditGate.evidenceContradiction(
            artifact: artifact,
            evidenceReceipt: evidence
        ))
    }

    func testRejectsIncorrectExplicitMeanBeforeValidatorExecution() throws {
        let artifact = """
        (317.671 + 319.082 + 319.799 + 320.795 + 321.465 + 322.561 + 323.048 +
        323.976 + 324.800 + 324.122 + 324.054) / 11 = 322.3075
        """
        let issue = try XCTUnwrap(AgentArtifactContractAuditGate.evidenceContradiction(
            artifact: artifact,
            evidenceReceipt: "retained source evidence"
        ))
        XCTAssertTrue(issue.contains("321.943000"))
        XCTAssertTrue(issue.contains("322.3075"))
    }

    func testAllowsCorrectExplicitMean() {
        let artifact = """
        (317.671 + 319.082 + 319.799 + 320.795 + 321.465 + 322.561 + 323.048 +
        323.976 + 324.800 + 324.122 + 324.054) / 11 = 321.943
        """
        XCTAssertNil(AgentArtifactContractAuditGate.evidenceContradiction(
            artifact: artifact,
            evidenceReceipt: "retained source evidence"
        ))
    }

    func testRejectsIncorrectExplicitMeanWithMarkdownEmphasis() throws {
        let artifact = """
        (317.671 + 319.082 + 319.799 + 320.795 + 321.465 + 322.561 + 323.048 +
        323.976 + 324.800 + 324.122 + 324.054) / 11 = **321.466**
        """
        let issue = try XCTUnwrap(AgentArtifactContractAuditGate.evidenceContradiction(
            artifact: artifact,
            evidenceReceipt: "retained source evidence"
        ))

        XCTAssertTrue(issue.contains("321.943000"), issue)
        XCTAssertTrue(issue.contains("321.466"), issue)
    }

    func testAllowsCorrectExplicitMeanWithMarkdownEmphasis() {
        let artifact = """
        (317.671 + 319.082 + 319.799 + 320.795 + 321.465 + 322.561 + 323.048 +
        323.976 + 324.800 + 324.122 + 324.054) / 11 = **321.943**
        """
        XCTAssertNil(AgentArtifactContractAuditGate.evidenceContradiction(
            artifact: artifact,
            evidenceReceipt: "retained source evidence"
        ))
    }

    func testRejectsIncorrectExplicitProductDivision() throws {
        let artifact = "2023 real = 4,200,000 × 333.952 / 304.702 = $4,603,818"
        let issue = try XCTUnwrap(AgentArtifactContractAuditGate.evidenceContradiction(
            artifact: artifact,
            evidenceReceipt: "retained source evidence"
        ))

        XCTAssertTrue(issue.contains("4603180.812729"), issue)
        XCTAssertTrue(issue.contains("$4,603,818"), issue)
    }

    func testRejectsIncorrectExplicitProductDivisionWithMarkdownEmphasis() throws {
        let artifact = "**2023 real** = **4,200,000** × (333.952 / 304.702) = **$4,603,818**"
        let issue = try XCTUnwrap(AgentArtifactContractAuditGate.evidenceContradiction(
            artifact: artifact,
            evidenceReceipt: "retained source evidence"
        ))

        XCTAssertTrue(issue.contains("4603180.812729"), issue)
        XCTAssertTrue(issue.contains("$4,603,818"), issue)
    }

    func testAllowsCorrectExplicitProductDivisionRoundedToDollar() {
        let artifact = "2023 real = 4,200,000 × 333.952 / 304.702 = $4,603,181"
        XCTAssertNil(AgentArtifactContractAuditGate.evidenceContradiction(
            artifact: artifact,
            evidenceReceipt: "retained source evidence"
        ))
    }

    func testAllowsCorrectChainedProductDivisionRoundedToDollar() {
        let artifact = "2023 real = $4,200,000 × (333.952 / 304.702) "
            + "= $4,200,000 × 1.0959954 = $4,603,181"
        XCTAssertNil(AgentArtifactContractAuditGate.evidenceContradiction(
            artifact: artifact,
            evidenceReceipt: "retained source evidence"
        ))
    }

    func testRejectsIncorrectChainedProductDivisionFinalValue() throws {
        let artifact = "2023 real = $4,200,000 × (333.952 / 304.702) "
            + "= $4,200,000 × 1.0959954 = $4,603,818"
        let issue = try XCTUnwrap(AgentArtifactContractAuditGate.evidenceContradiction(
            artifact: artifact,
            evidenceReceipt: "retained source evidence"
        ))

        XCTAssertTrue(issue.contains("4603180.812729"), issue)
        XCTAssertTrue(issue.contains("$4,603,818"), issue)
    }

    func testRejectsIncorrectExplicitGrowthRate() throws {
        let artifact = "(5,429,439 − 4,603,181) / 4,603,181 = 18.50%"
        let issue = try XCTUnwrap(AgentArtifactContractAuditGate.evidenceContradiction(
            artifact: artifact,
            evidenceReceipt: "retained source evidence"
        ))

        XCTAssertTrue(issue.contains("explicit growth equation"), issue)
        XCTAssertTrue(issue.contains("18.50%"), issue)
    }

    func testRejectsIncorrectExplicitGrowthRateInsideInlineCode() throws {
        let artifact = "`(5,429,439 − 4,603,181) / 4,603,181 = 18.50%`"
        let issue = try XCTUnwrap(AgentArtifactContractAuditGate.evidenceContradiction(
            artifact: artifact,
            evidenceReceipt: "retained source evidence"
        ))

        XCTAssertTrue(issue.contains("explicit growth equation"), issue)
        XCTAssertTrue(issue.contains("18.50%"), issue)
    }

    func testRejectsConflictingRepeatedMarkdownTableField() throws {
        let artifact = """
        | fiscal_year | real_revenue_usd |
        |---|---|
        | 2023 | $4,603,451 |

        | fiscal_year | real_revenue_usd |
        |---|---|
        | 2023 | $4,603,181 |
        """
        let issue = try XCTUnwrap(AgentArtifactContractAuditGate.evidenceContradiction(
            artifact: artifact,
            evidenceReceipt: "retained source evidence"
        ))

        XCTAssertTrue(issue.contains("conflicting values"), issue)
        XCTAssertTrue(issue.contains("$4,603,451"), issue)
        XCTAssertTrue(issue.contains("$4,603,181"), issue)
    }

    func testRejectsMeanThatConflictsWithMonthlyTable() throws {
        let artifact = """
        The 2025 observed-month proxy mean is 321.4650.

        ### Detailed 2025 monthly indexes
        | Month | Index |
        |---|---|
        | Jan | 317.671 |
        | Feb | 319.082 |
        | Mar | 319.799 |
        | Apr | 320.795 |
        | May | 321.465 |
        | Jun | 322.561 |
        | Jul | 323.048 |
        | Aug | 323.976 |
        | Sep | 324.800 |
        | Oct | unavailable |
        | Nov | 324.122 |
        | Dec | 324.054 |
        """
        let issue = try XCTUnwrap(AgentArtifactContractAuditGate.evidenceContradiction(
            artifact: artifact,
            evidenceReceipt: "retained source evidence"
        ))

        XCTAssertTrue(issue.contains("321.943000"), issue)
        XCTAssertTrue(issue.contains("321.4650"), issue)
    }

    func testRejectsAnnualProxyThatConflictsWithRetainedMonthlySourceTable() throws {
        let evidence = """
        | Year | Jan | Feb | Mar | Apr | May | Jun | Jul | Aug | Sep | Oct | Nov | Dec | HALF1 | HALF2 |
        | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
        | 2023 | 299.170 | 300.840 | 301.836 | 303.363 | 304.127 | 305.109 | 305.691 | 307.026 | 307.789 | 307.671 | 307.051 | 306.746 | 302.408 | 306.996 |
        | 2024 | 308.417 | 310.326 | 312.332 | 313.548 | 314.069 | 314.175 | 314.540 | 314.796 | 315.301 | 315.664 | 315.493 | 315.605 | 312.145 | 315.233 |
        | 2025 | 317.671 | 319.082 | 319.799 | 320.795 | 321.465 | 322.561 | 323.048 | 323.976 | 324.800 | -(X) | 324.122 | 324.054 | 320.229 | 324.000 |
        | 2026 | 325.252 | 326.785 | 330.213 | 333.020 | 335.123 | 333.952 | | | | | | | 330.724 | |
        """
        let artifact = """
        | Basis | Basis type | Index |
        | --- | --- | --- |
        | 2023 | Annual average | 304.702 |
        | 2024 | Annual average | 313.689 |
        | 2025 | Observed-month proxy | 322.536 |
        | 2026 | June monthly benchmark | 333.952 |
        """

        let issue = try XCTUnwrap(AgentArtifactContractAuditGate.evidenceContradiction(
            artifact: artifact,
            evidenceReceipt: evidence
        ))

        XCTAssertTrue(issue.contains("321.943000"), issue)
        XCTAssertTrue(issue.contains("11 published values"), issue)
        XCTAssertTrue(issue.contains("322.536"), issue)
        XCTAssertTrue(issue.contains("Oct"), issue)
    }

    func testRejectsAnnualAverageTableValueBeforeTypeLabel() throws {
        let evidence = """
        | Year | Jan | Feb | Mar | Apr | May | Jun | Jul | Aug | Sep | Oct | Nov | Dec |
        | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
        | 2024 | 308.417 | 310.326 | 312.332 | 313.548 | 314.069 | 314.175 | 314.540 | 314.796 | 315.301 | 315.664 | 315.493 | 315.605 |
        """
        let artifact = """
        | Year | CPI basis | Type |
        | --- | --- | --- |
        | 2024 | **314.556** | annual average |
        """

        let issue = try XCTUnwrap(AgentArtifactContractAuditGate.evidenceContradiction(
            artifact: artifact,
            evidenceReceipt: evidence
        ))
        XCTAssertTrue(issue.contains("313.688833"), issue)
        XCTAssertTrue(issue.contains("314.556"), issue)
    }

    func testAllowsAnnualProxyDerivedFromRetainedMonthlySourceTable() {
        let evidence = """
        | Year | Jan | Feb | Mar | Apr | May | Jun | Jul | Aug | Sep | Oct | Nov | Dec | HALF1 | HALF2 |
        | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
        | 2025 | 317.671 | 319.082 | 319.799 | 320.795 | 321.465 | 322.561 | 323.048 | 323.976 | 324.800 | -(X) | 324.122 | 324.054 | 320.229 | 324.000 |
        """
        let artifact = "The 2025 observed-month proxy average is 321.943."

        XCTAssertNil(AgentArtifactContractAuditGate.evidenceContradiction(
            artifact: artifact,
            evidenceReceipt: evidence
        ))
    }

    func testAllowsProxyInCanonicalRevenueTableAfterNominalAmount() {
        let evidence = """
        | Year | Jan | Feb | Mar | Apr | May | Jun | Jul | Aug | Sep | Oct | Nov | Dec |
        | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
        | 2025 | 317.671 | 319.082 | 319.799 | 320.795 | 321.465 | 322.561 | 323.048 | 323.976 | 324.800 | -(X) | 324.122 | 324.054 |
        """
        let artifact = """
        | Fiscal year | Nominal revenue | CPI basis type | Selected CPI basis index | Real revenue (June 2026 dollars) | Nominal YoY growth | Real YoY growth |
        |---|---|---|---|---|---|---|
        | 2025 | $6,000,000 | Observed-month proxy (11/12 months, Oct missing) | 321.943 | $6,223,810 | 17.65% | 14.63% |
        """

        XCTAssertNil(AgentArtifactContractAuditGate.evidenceContradiction(
            artifact: artifact,
            evidenceReceipt: evidence
        ))
    }

    func testMonthlyMeanAuditUsesSelectedCPIColumnInsteadOfNominalRevenue() throws {
        let evidence = """
        | Year | Jan | Feb | Mar | Apr | May | Jun | Jul | Aug | Sep | Oct | Nov | Dec |
        | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
        | 2025 | 317.671 | 319.082 | 319.799 | 320.795 | 321.465 | 322.561 | 323.048 | 323.976 | 324.800 | -(X) | 324.122 | 324.054 |
        """
        let artifact = """
        ### 2025 observed-month proxy

        | Month | 2025 CPI |
        |---|---|
        | Jan | 317.671 |
        | Feb | 319.082 |
        | Mar | 319.799 |
        | Apr | 320.795 |
        | May | 321.465 |
        | Jun | 322.561 |
        | Jul | 323.048 |
        | Aug | 323.976 |
        | Sep | 324.800 |
        | Nov | 324.122 |
        | Dec | 324.054 |

        Mean = 322.852. This is an observed-month proxy.

        | fiscal_year | nominal_revenue_usd | selected CPI basis | real_revenue_usd |
        |---|---|---|---|
        | 2025 | $6,000,000 | 322.852 (proxy) | $6,206,290 |
        """

        let issue = try XCTUnwrap(AgentArtifactContractAuditGate.evidenceContradiction(
            artifact: artifact,
            evidenceReceipt: evidence
        ))
        XCTAssertTrue(issue.contains("not 322.852"), issue)
        XCTAssertFalse(issue.contains("not $6,000,000"), issue)
    }

    func testRejectsWrongProxyColumnWithoutTreatingNominalRevenueAsClaim() throws {
        let evidence = """
        | Year | Jan | Feb | Mar | Apr | May | Jun | Jul | Aug | Sep | Oct | Nov | Dec |
        | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
        | 2025 | 317.671 | 319.082 | 319.799 | 320.795 | 321.465 | 322.561 | 323.048 | 323.976 | 324.800 | -(X) | 324.122 | 324.054 |
        """
        let artifact = """
        | Fiscal year | Nominal revenue | CPI basis type | Selected CPI basis index | Real revenue (June 2026 dollars) | Nominal YoY growth | Real YoY growth |
        |---|---|---|---|---|---|---|
        | 2025 | $6,000,000 | Observed-month proxy (11/12 months, Oct missing) | 322.875 | $6,206,553 | 17.65% | 14.30% |
        """

        let issue = try XCTUnwrap(AgentArtifactContractAuditGate.evidenceContradiction(
            artifact: artifact,
            evidenceReceipt: evidence
        ))
        XCTAssertTrue(issue.contains("322.875"), issue)
        XCTAssertFalse(issue.contains("not $6,000,000"), issue)
    }

    func testBatchesEveryTask126SourceAndArithmeticContradiction() throws {
        let evidence = """
        | Year | Jan | Feb | Mar | Apr | May | Jun | Jul | Aug | Sep | Oct | Nov | Dec | HALF1 | HALF2 |
        | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
        | 2023 | 299.170 | 300.840 | 301.836 | 303.363 | 304.127 | 305.109 | 305.691 | 307.026 | 307.789 | 307.671 | 307.051 | 306.746 | 302.408 | 306.996 |
        | 2024 | 308.417 | 310.326 | 312.332 | 313.548 | 314.069 | 314.175 | 314.540 | 314.796 | 315.301 | 315.664 | 315.493 | 315.605 | 312.145 | 315.233 |
        | 2025 | 317.671 | 319.082 | 319.799 | 320.795 | 321.465 | 322.561 | 323.048 | 323.976 | 324.800 | -(X) | 324.122 | 324.054 | 320.229 | 324.000 |
        | 2026 | 325.252 | 326.785 | 330.213 | 333.020 | 335.123 | 333.952 | | | | | | | 330.724 | |
        """
        let artifact = """
        | Year | CPI basis type | Selected CPI basis index |
        | --- | --- | --- |
        | 2023 | Annual average | 304.702 |
        | 2024 | Annual average | 313.689 |
        | 2025 | Observed-month proxy | 322.533 |
        | 2026 | Latest monthly benchmark (June) | 333.952 |

        2023 real = $4,200,000 × (333.952 / 304.702) = $4,603,178
        2024 real = $5,100,000 × (333.952 / 313.689) = $5,429,365
        2025 real = $6,000,000 × (333.952 / 321.943) = $6,212,157
        """

        let issue = try XCTUnwrap(AgentArtifactContractAuditGate.evidenceContradiction(
            artifact: artifact,
            evidenceReceipt: evidence
        ))

        XCTAssertTrue(issue.contains("independent deterministic contradictions"), issue)
        XCTAssertTrue(issue.contains("4603180.812729"), issue)
        XCTAssertTrue(issue.contains("5429438.711590"), issue)
        XCTAssertTrue(issue.contains("6223809.804841"), issue)
        XCTAssertTrue(issue.contains("2023 monthly mean = 304.701583"), issue)
        XCTAssertTrue(issue.contains("2024 monthly mean = 313.688833"), issue)
        XCTAssertTrue(issue.contains("2025 monthly mean = 321.943000"), issue)
        XCTAssertTrue(issue.contains("322.533"), issue)
        XCTAssertTrue(issue.contains("missing/non-numeric Oct"), issue)
    }

    func testAcceptsTask126RoundedDisplayBasisAndLatestMonthlyBenchmark() {
        let evidence = """
        | Year | Jan | Feb | Mar | Apr | May | Jun | Jul | Aug | Sep | Oct | Nov | Dec | HALF1 | HALF2 |
        | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
        | 2023 | 299.170 | 300.840 | 301.836 | 303.363 | 304.127 | 305.109 | 305.691 | 307.026 | 307.789 | 307.671 | 307.051 | 306.746 | 302.408 | 306.996 |
        | 2024 | 308.417 | 310.326 | 312.332 | 313.548 | 314.069 | 314.175 | 314.540 | 314.796 | 315.301 | 315.664 | 315.493 | 315.605 | 312.145 | 315.233 |
        | 2025 | 317.671 | 319.082 | 319.799 | 320.795 | 321.465 | 322.561 | 323.048 | 323.976 | 324.800 | -(X) | 324.122 | 324.054 | 320.229 | 324.000 |
        | 2026 | 325.252 | 326.785 | 330.213 | 333.020 | 335.123 | 333.952 | | | | | | | 330.724 | |
        """
        let artifact = """
        | Year | Basis selected | CPI index | Observation count |
        |---|---|---|---|
        | 2023 | Calendar-year annual average | 304.702 | 12 months |
        | 2024 | Calendar-year annual average | 313.689 | 12 months |
        | 2025 | Observed-month proxy | 321.943 | 11 months (Oct missing) |
        | 2026 | Latest monthly benchmark (June 2026) | 333.952 | 1 month |

        The 2026 benchmark CPI is June 2026 = 333.952, a monthly benchmark, not a
        completed annual average.

        `real revenue = nominal revenue x (333.952 / selected CPI basis)`

        | Fiscal year | Nominal revenue | CPI basis | Real revenue (June-2026 $) |
        |---|---|---|---|
        | 2023 | $4,200,000 | 304.702 | $4,603,187 |
        | 2024 | $5,100,000 | 313.689 | $5,429,442 |
        | 2025 | $6,000,000 | 321.943 | $6,223,810 |

        - 2023: $4,200,000 x (333.952 / 304.701583) = $4,603,187
        - 2024: $5,100,000 x (333.952 / 313.688833) = $5,429,442
        - 2025: $6,000,000 x (333.952 / 321.943) = $6,223,810
        """

        XCTAssertNil(AgentArtifactContractAuditGate.evidenceContradiction(
            artifact: artifact,
            evidenceReceipt: evidence
        ))
    }

    func testRejectsTask126DerivedRowsAndHalfPeriodRelabeling() throws {
        let evidence = """
        | Year | Jan | Feb | Mar | Apr | May | Jun | Jul | Aug | Sep | Oct | Nov | Dec | HALF1 | HALF2 |
        | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
        | 2023 | 299.170 | 300.840 | 301.836 | 303.363 | 304.127 | 305.109 | 305.691 | 307.026 | 307.789 | 307.671 | 307.051 | 306.746 | 302.408 | 306.996 |
        | 2024 | 308.417 | 310.326 | 312.332 | 313.548 | 314.069 | 314.175 | 314.540 | 314.796 | 315.301 | 315.664 | 315.493 | 315.605 | 312.145 | 315.233 |
        | 2025 | 317.671 | 319.082 | 319.799 | 320.795 | 321.465 | 322.561 | 323.048 | 323.976 | 324.800 | -(X) | 324.122 | 324.054 | 320.229 | 324.000 |
        """
        let artifact = """
        | Year | Basis index | Notes |
        |---|---|---|
        | 2023 | 304.701583 | BLS annual-average column shows 306.996. |
        | 2024 | 313.688833 | BLS annual-average column shows 315.233. |
        | 2025 | 321.943000 | observed-month proxy |

        `real revenue = nominal revenue x (333.952 / selected CPI basis)`

        | Fiscal year | Nominal revenue ($) | CPI basis | Real revenue ($, rounded) |
        |---|---|---|---|
        | 2023 | $4,200,000 | 304.701583 | $4,603,276 |
        | 2024 | $5,100,000 | 313.688833 | $5,429,444 |
        | 2025 | $6,000,000 | 321.943000 | $6,223,805 |
        """

        let issue = try XCTUnwrap(AgentArtifactContractAuditGate.evidenceContradiction(
            artifact: artifact,
            evidenceReceipt: evidence
        ))

        XCTAssertTrue(issue.contains("derived amount"), issue)
        XCTAssertTrue(issue.contains("4603187.112421"), issue)
        XCTAssertTrue(issue.contains("HALF2"), issue)
        XCTAssertTrue(issue.contains("306.996"), issue)
        XCTAssertTrue(issue.contains("315.233"), issue)
    }

    func testSemanticAuditFailureRequiresDeliverableRepair() {
        XCTAssertTrue(AgentArtifactContractAuditGate.failedAuditRequiresDeliverableRepair(
            "FAIL\n2025 real revenue: expected 6223810, actual 6223805"
        ))
        XCTAssertTrue(AgentArtifactContractAuditGate.failedAuditRequiresDeliverableRepair(
            "AssertionError: row count mismatch"
        ))
        XCTAssertFalse(AgentArtifactContractAuditGate.failedAuditRequiresDeliverableRepair(
            "SyntaxError: unterminated string literal"
        ))
        XCTAssertFalse(AgentArtifactContractAuditGate.failedAuditRequiresDeliverableRepair(
            "ModuleNotFoundError: No module named 'pandas'"
        ))
        XCTAssertFalse(AgentArtifactContractAuditGate.failedAuditRequiresDeliverableRepair(
            "Traceback (most recent call last):\n  File \"validate.py\", line 19\nKeyError: 2023"
        ))
        XCTAssertFalse(AgentArtifactContractAuditGate.failedAuditRequiresDeliverableRepair(
            "Traceback (most recent call last):\n  File \"validate.py\", line 21\n"
                + "ValueError: invalid format string"
        ))
        XCTAssertTrue(AgentArtifactContractAuditGate.failedAuditRequiresDeliverableRepair(
            "VALIDATION REJECTED: July conflicts with June source data.\n\n"
                + "Traceback (most recent call last):\nKeyError: 2026"
        ))
    }

    func testRetainsSourceTableRowsAcrossFocusedReceiptOmissionMarker() throws {
        let evidence = """
        Successful host.web.fetch observation:
        | Year | Jan | Feb | Mar | Apr | May | Jun | Jul | Aug | Sep | Oct | Nov | Dec | HALF1 | HALF2 |
        | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
        | 2016 | 236.916 | 237.111 | 238.132 | 239.261 | 240.229 | 241.018 | 240.628 | 240.849 | 241.428 | 241.729 | 241.353 | 241.432 | 238.778 | 241.237 |
        [... 4 non-matching lines omitted ...]
        | 2023 | 299.170 | 300.840 | 301.836 | 303.363 | 304.127 | 305.109 | 305.691 | 307.026 | 307.789 | 307.671 | 307.051 | 306.746 | 302.408 | 306.996 |
        | 2024 | 308.417 | 310.326 | 312.332 | 313.548 | 314.069 | 314.175 | 314.540 | 314.796 | 315.301 | 315.664 | 315.493 | 315.605 | 312.145 | 315.233 |
        | 2025 | 317.671 | 319.082 | 319.799 | 320.795 | 321.465 | 322.561 | 323.048 | 323.976 | 324.800 | -(X) | 324.122 | 324.054 | 320.229 | 324.000 |
        """
        let artifact = """
        | Year | Selected CPI basis | Basis type | Notes |
        | --- | ---: | --- | --- |
        | 2023 | 304.702 | **Annual average** | Full 12-month mean = 304.702. |
        | 2024 | 314.688 | **Annual average** | Full 12-month mean = 314.688. |
        | 2025 | 321.943 | **Observed-month proxy** | Mean of 11 published months = 321.943. |
        """

        let issue = try XCTUnwrap(AgentArtifactContractAuditGate.evidenceContradiction(
            artifact: artifact,
            evidenceReceipt: evidence
        ))
        XCTAssertTrue(issue.contains("2024 monthly observations average to 313.688833"), issue)
        XCTAssertTrue(issue.contains("not 314.688"), issue)
    }

    func testAcceptsCommaFormattedChainedSumDivisionEquation() {
        let artifact = """
        (317.671 + 319.082 + 319.799 + 320.795 + 321.465 + 322.561 + 323.048 + 323.976 + 324.800 + 324.122 + 324.054) / 11 = 3,541.373 / 11 = 321.943
        """

        XCTAssertNil(AgentArtifactContractAuditGate.evidenceContradiction(
            artifact: artifact,
            evidenceReceipt: "no structured source values"
        ))
    }

    func testRejectsWrongCommaFormattedChainedSumSubtotal() throws {
        let artifact = """
        (317.671 + 319.082 + 319.799 + 320.795 + 321.465 + 322.561 + 323.048 + 323.976 + 324.800 + 324.122 + 324.054) / 11 = 3,541.999 / 11 = 321.943
        """

        let issue = try XCTUnwrap(AgentArtifactContractAuditGate.evidenceContradiction(
            artifact: artifact,
            evidenceReceipt: "no structured source values"
        ))
        XCTAssertTrue(issue.contains("chained sum subtotal"), issue)
        XCTAssertTrue(issue.contains("3541.373000"), issue)
    }

    private func makeWorkspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("artifact-contract-audit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    func testRecognizesExplicitMachineCheckableArtifactContract() {
        XCTAssertTrue(AgentArtifactContractAuditGate.requiresAudit(
            in: "The table must have exactly four company rows. The first five cells in every row must be ordered."
        ))
        XCTAssertTrue(AgentArtifactContractAuditGate.requiresAudit(
            in: "Put every company in the same <tr> as its values."
        ))
        XCTAssertTrue(AgentArtifactContractAuditGate.requiresAudit(
            in: "Restate every nominal revenue row with the selected CPI basis."
        ))
        XCTAssertTrue(AgentArtifactContractAuditGate.requiresAudit(
            in: "Run a deterministic post-write validator against the report."
        ))
        XCTAssertFalse(AgentArtifactContractAuditGate.requiresAudit(
            in: "Draft exactly three emails for each of six prospects, and include a CTA in every email."
        ))
        XCTAssertFalse(AgentArtifactContractAuditGate.requiresAudit(
            in: "Create a polished comparison report with a useful table."
        ))
    }

    func testOnlyValidatorCommandsAuditTheReferencedArtifact() {
        let path = "outputs/report.html"
        let readback = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "cat outputs/report.html"])
        )
        XCTAssertTrue(AgentArtifactContractAuditGate.auditedPaths(
            for: readback,
            among: [path]
        ).isEmpty)

        let echoedAssertion = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json([
                "cmd": "echo 'assert outputs/report.html is valid'",
            ])
        )
        XCTAssertTrue(AgentArtifactContractAuditGate.auditedPaths(
            for: echoedAssertion,
            among: [path]
        ).isEmpty)

        let unrelated = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json([
                "cmd": "python3 -c \"assert open('inputs/source.csv').read()\"",
            ])
        )
        XCTAssertTrue(AgentArtifactContractAuditGate.auditedPaths(
            for: unrelated,
            among: [path]
        ).isEmpty)

        let validator = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json([
                "cmd": "python3 -c \"assert open('outputs/report.html').read().count('<tr>') == 4\"",
            ])
        )
        XCTAssertEqual(AgentArtifactContractAuditGate.auditedPaths(
            for: validator,
            among: [path]
        ), [path])
    }

    func testValidatorScriptWithDescriptiveUnderscoreNameAuditsArtifact() {
        let path = "outputs/report.md"
        let validator = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json([
                "cmd": "python3 scripts/check_deliverable.py outputs/report.md",
            ])
        )

        XCTAssertEqual(
            AgentArtifactContractAuditGate.auditedPaths(for: validator, among: [path]),
            [path]
        )
    }

    func testCorrectionBudgetIsBoundedPerArtifact() {
        let tools = [ToolDefinition.shellRun]
        XCTAssertNotNil(AgentArtifactContractAuditGate.correction(
            path: "outputs/report.html",
            tools: tools,
            correctionCount: AgentArtifactContractAuditGate.correctionLimitPerPath - 1,
            userMessage: "Write outputs/report.html."
        ))
        XCTAssertNil(AgentArtifactContractAuditGate.correction(
            path: "outputs/report.html",
            tools: tools,
            correctionCount: AgentArtifactContractAuditGate.correctionLimitPerPath,
            userMessage: "Write outputs/report.html."
        ))
    }

    func testCorrectionRequiresSourceTableAndParserIntegrity() throws {
        let correction = try XCTUnwrap(AgentArtifactContractAuditGate.correction(
            path: "outputs/report.md",
            tools: [.shellRun],
            correctionCount: 0,
            userMessage: "Use the latest 2026 CPI benchmark and write outputs/report.md."
        ))

        XCTAssertTrue(correction.prompt.contains("align every value with its exact source header"))
        XCTAssertTrue(correction.prompt.contains("Never relabel a half-period"))
        XCTAssertTrue(correction.prompt.contains("HALF1, HALF2, H1, and H2 columns are never annual values"))
        XCTAssertTrue(correction.prompt.contains("underlying observations independently"))
        XCTAssertTrue(correction.prompt.contains("locate intended table fields by their headers"))
        XCTAssertTrue(correction.prompt.contains("Whole-document approximate-number searches are invalid"))
        XCTAssertTrue(correction.prompt.contains("half of the artifact's displayed rounding unit"))
        XCTAssertTrue(correction.prompt.contains("conflicting repeated values"))
        XCTAssertTrue(correction.prompt.contains("rightmost non-missing eligible period"))
        XCTAssertTrue(correction.prompt.contains("selected period label and value"))
        XCTAssertTrue(correction.prompt.contains("expected values copied from the artifact"))
        XCTAssertTrue(correction.prompt.contains("Use the latest 2026 CPI benchmark"))
        XCTAssertTrue(correction.prompt.contains("model-authored validator"))
    }

    func testCorrectionRetainsNamedFailedValidatorAssertions() throws {
        let correction = try XCTUnwrap(AgentArtifactContractAuditGate.correction(
            path: "outputs/report.md",
            tools: [.shellRun],
            correctionCount: 1,
            userMessage: "Restate revenue in 2026 dollars.",
            failedAuditReceipt: "VALIDATION FAILED\n2025: expected $6,223,810"
        ))

        XCTAssertTrue(correction.prompt.contains("authoritative record of the audit failure"))
        XCTAssertTrue(correction.prompt.contains("2025: expected $6,223,810"))
        XCTAssertTrue(correction.prompt.contains("typography-, whitespace-, or Markdown-only"))
        XCTAssertTrue(correction.prompt.contains("until a subsequent validator execution passes"))
    }

    func testRunnerRequiresAuditAndReauditsAfterRewrite() async throws {
        let root = try makeWorkspace()
        let firstWrite = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/report.html",
                "content": "<table><tr><td>Atlas</td></tr></table>",
            ])
        )
        let validator = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json([
                "cmd": "python3 -c \"assert open('outputs/report.html').read().count('<tr>') == 4\"",
            ])
        )
        let secondWrite = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/report.html",
                "content": "<table><tr><td>Atlas</td></tr><tr><td>Asana</td></tr>"
                    + "<tr><td>monday.com</td></tr><tr><td>GitLab</td></tr></table>",
            ])
        )
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [
                .tool(firstWrite),
                .say("The report is complete."),
                .tool(validator),
                .tool(secondWrite),
                .say("The corrected report is complete."),
                .tool(validator),
                .say("The audited report is complete."),
                .say("The audited report is complete and verified."),
            ]),
            safety: AlwaysApprovingSafetyReviewer(),
            toolExecutionOverride: { call, _ in
                guard call.name == ToolDefinition.shellRun.name else { return nil }
                return ToolResult(ok: true, stdout: "PASS: artifact contract\n")
            },
            maxToolSteps: 10
        )

        let result = try await runner.send(
            """
            Save the deliverable to outputs/report.html. Its table must contain exactly four \
            company rows, and the first five cells in every company row must be company and four \
            raw numeric values. Before finishing, verify the saved deliverable.
            """,
            in: ChatThread(title: "contract audit"),
            workspaceRoot: root
        )

        XCTAssertEqual(
            result.toolResults.count,
            6,
            "two writes each need an immediate readback and a deterministic contract audit"
        )
        XCTAssertTrue(result.toolResults.allSatisfy(\.ok))
        XCTAssertEqual(
            result.thread.events.filter {
                $0.kind == .notice && $0.summary.contains("deterministic contract audit")
            }.count,
            2
        )
        XCTAssertEqual(
            result.thread.messages.last?.content,
            "The audited report is complete."
        )
    }

    func testRunnerStopsHonestlyAfterRepeatedlyIgnoredAuditCorrections() async throws {
        let root = try makeWorkspace()
        let write = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/report.html",
                "content": "<table><tr><td>Atlas</td></tr></table>",
            ])
        )
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [
                .tool(write),
                .say("Done."),
                .say("Done."),
                .say("Done."),
                .say("Done."),
            ]),
            safety: AlwaysApprovingSafetyReviewer(),
            maxToolSteps: 10
        )

        let result = try await runner.send(
            "Save outputs/report.html with exactly four company rows and verify it before finishing.",
            in: ChatThread(title: "bounded contract audit"),
            workspaceRoot: root
        )

        guard case .flailDetected(let reason) = result.stopReason else {
            return XCTFail("expected bounded audit stop, got \(result.stopReason)")
        }
        XCTAssertTrue(reason.contains("outputs/report.html"))
        XCTAssertTrue(reason.contains("deterministic contract audit"))
        XCTAssertEqual(
            result.thread.events.filter {
                $0.kind == .notice && $0.summary.contains("required a deterministic contract audit")
            }.count,
            AgentArtifactContractAuditGate.correctionLimitPerPath
        )
        XCTAssertEqual(result.toolResults.count, 1)
    }
}
