import Foundation
import XCTest
import QuillCodeCore
@testable import QuillCodeAgent

final class AuxiliaryModelSelectorTests: XCTestCase {
    func testPicksCheapRecentModelOverFlagship() {
        let selection = AuxiliaryModelSelector.selection(
            models: [
                pricedModel(id: "acme/flagship", input: 15, output: 75, released: days(100)),
                pricedModel(id: "acme/workhorse", input: 3, output: 15, released: days(200)),
                pricedModel(id: "acme/tiny", input: 0.1, output: 0.4, released: days(300))
            ],
            sessionModelID: "acme/flagship"
        )

        XCTAssertEqual(selection.modelID, "acme/tiny")
        XCTAssertEqual(selection.source, .catalogHeuristic)
    }

    func testCostOutweighsRecency() {
        let selection = AuxiliaryModelSelector.selection(
            models: [
                pricedModel(id: "acme/cheap-old", input: 0.1, output: 0.4, released: days(10)),
                pricedModel(id: "acme/pricey-new", input: 2, output: 8, released: days(900))
            ],
            sessionModelID: "acme/flagship"
        )

        XCTAssertEqual(selection.modelID, "acme/cheap-old")
    }

    func testRecencyBreaksCostTies() {
        let selection = AuxiliaryModelSelector.selection(
            models: [
                pricedModel(id: "acme/gen-one", input: 0.5, output: 1.5, released: days(10)),
                pricedModel(id: "acme/gen-two", input: 0.5, output: 1.5, released: days(500))
            ],
            sessionModelID: "acme/flagship"
        )

        XCTAssertEqual(selection.modelID, "acme/gen-two")
    }

    func testSmallModelNameBiasWinsAtEqualPrice() {
        for hint in ["nano", "flash", "lite", "haiku", "mini"] {
            let selection = AuxiliaryModelSelector.selection(
                models: [
                    pricedModel(id: "acme/aaa-standard", input: 0.5, output: 1.5),
                    pricedModel(id: "acme/zzz-\(hint)", input: 0.5, output: 1.5)
                ],
                sessionModelID: "acme/flagship"
            )
            XCTAssertEqual(selection.modelID, "acme/zzz-\(hint)")
        }
    }

    func testSmallModelNameBiasAbsorbsSmallCostGap() {
        let selection = AuxiliaryModelSelector.selection(
            models: [
                pricedModel(id: "acme/base", input: 0.5, output: 1.5),
                pricedModel(id: "acme/base-mini", input: 0.55, output: 1.65)
            ],
            sessionModelID: "acme/flagship"
        )

        XCTAssertEqual(selection.modelID, "acme/base-mini")
    }

    func testNameBiasMatchesTokensNotSubstrings() {
        // "gemini" and "minimax" contain "mini" as a raw substring; neither is a small model, so
        // neither may collect the bonus. Layout mirrors the absorb test above: if the bonus applied,
        // the fractionally pricier model would win.
        for impostor in ["acme/gemini-3-pro", "acme/minimax-x1"] {
            let selection = AuxiliaryModelSelector.selection(
                models: [
                    pricedModel(id: "acme/base", input: 0.5, output: 1.5),
                    pricedModel(id: impostor, input: 0.55, output: 1.65)
                ],
                sessionModelID: "acme/flagship"
            )
            XCTAssertEqual(selection.modelID, "acme/base")
        }
    }

    func testGeminiUltraFlagshipNeverWinsViaAccidentalMiniSubstring() {
        // Regression: with substring matching, gemini-3-ultra (the priciest model here) collected
        // the "mini" bonus and was selected as the "cheap" auxiliary model.
        let selection = AuxiliaryModelSelector.selection(
            models: [
                pricedModel(id: "google/gemini-3-ultra", input: 20, output: 80),
                pricedModel(id: "anthropic/claude-4-opus", input: 15, output: 75)
            ],
            sessionModelID: "anthropic/claude-4-opus"
        )

        XCTAssertEqual(selection.modelID, "anthropic/claude-4-opus")
    }

    func testFlashTokenInsideRealModelNameStillGetsBonus() {
        // Token matching must not lose true positives: gemini-2.5-flash carries a real "flash" token.
        let selection = AuxiliaryModelSelector.selection(
            models: [
                pricedModel(id: "acme/standard", input: 0.5, output: 1.5),
                pricedModel(id: "google/gemini-2.5-flash", input: 0.55, output: 1.65)
            ],
            sessionModelID: "acme/flagship"
        )

        XCTAssertEqual(selection.modelID, "google/gemini-2.5-flash")
    }

    func testExpensiveOutlierCannotDiluteRealCostGaps() {
        // spendy-flash costs 62x the cheapest model. With range-based cost normalization the huge
        // outlier compressed that gap to ~0.01, letting recency + name bonus override it; the
        // ratio-to-cheapest score must keep the 62x gap dominant regardless of the outlier.
        let selection = AuxiliaryModelSelector.selection(
            models: [
                pricedModel(id: "acme/cheap", input: 0.05, output: 0.2, released: days(10)),
                pricedModel(id: "acme/spendy-flash", input: 3.1, output: 12.4, released: days(900)),
                pricedModel(id: "acme/mega", input: 500, output: 1500, released: days(500))
            ],
            sessionModelID: "acme/flagship"
        )

        XCTAssertEqual(selection.modelID, "acme/cheap")
    }

    func testNeverPicksModelPricierThanPricedSessionModel() {
        // zippy-mini wins the heuristic (name bonus absorbs its small premium) but is strictly
        // pricier than the session model — the aux call must never cost more than doing nothing.
        let models = [
            pricedModel(id: "acme/session-base", input: 1, output: 1),
            pricedModel(id: "acme/zippy-mini", input: 1.1, output: 1.1)
        ]

        let guarded = AuxiliaryModelSelector.selection(models: models, sessionModelID: "acme/session-base")
        XCTAssertEqual(guarded.modelID, "acme/session-base")
        XCTAssertEqual(guarded.source, .sessionModelCheaper)

        // Sanity: the ceiling only binds when the session model is priced in the catalog.
        let unguarded = AuxiliaryModelSelector.selection(models: models, sessionModelID: "acme/unpriced")
        XCTAssertEqual(unguarded.modelID, "acme/zippy-mini")
        XCTAssertEqual(unguarded.source, .catalogHeuristic)
    }

    func testNonFinitePricesAndDatesCannotPoisonSelection() {
        let infinitePrice = pricedModel(id: "acme/free-lunch-nano", input: .infinity, output: 0.1)
        let infiniteDate = pricedModel(
            id: "acme/undated",
            input: 0.2,
            output: 0.8,
            released: Date(timeIntervalSince1970: .infinity)
        )
        let sane = pricedModel(id: "acme/sane", input: 0.5, output: 2, released: days(100))
        let models = [infinitePrice, infiniteDate, sane]

        // The infinite price is not a candidate; the infinite date is ignored (neutral recency), so
        // the genuinely cheapest model wins and the result is order-independent (no NaN scores).
        let selection = AuxiliaryModelSelector.selection(models: models, sessionModelID: "acme/flagship")
        XCTAssertEqual(selection.modelID, "acme/undated")
        XCTAssertEqual(
            AuxiliaryModelSelector.selection(models: models.reversed(), sessionModelID: "acme/flagship").modelID,
            "acme/undated"
        )

        let onlyPoisoned = AuxiliaryModelSelector.selection(
            models: [infinitePrice],
            sessionModelID: "acme/flagship"
        )
        XCTAssertEqual(onlyPoisoned.modelID, "acme/flagship")
        XCTAssertEqual(onlyPoisoned.source, .sessionModelFallback)
    }

    func testFinitePricesWhoseBlendOverflowsCannotPoisonSelection() {
        // (3 * input + output) / 4 overflows to +inf for finite prices above ~6e307/Mtok. If such
        // blends became candidates, cheapestCost/cost = inf/inf = NaN would poison the scores,
        // break the comparator's strict weak ordering, and make the winner catalog-order-dependent.
        let junkA = pricedModel(id: "acme/junk-a", input: 7e307, output: 7e307)
        let junkB = pricedModel(id: "acme/junk-b", input: 1e308, output: 1e308)

        // Overflowing blends are not candidates at all: with nothing else in the catalog, both
        // orders fall back to the (unpriced) session model instead of picking order-dependent junk.
        for models in [[junkA, junkB], [junkB, junkA]] {
            let selection = AuxiliaryModelSelector.selection(models: models, sessionModelID: "acme/flagship")
            XCTAssertEqual(selection.modelID, "acme/flagship")
            XCTAssertEqual(selection.source, .sessionModelFallback)
        }

        // And a legitimately priced model beats the junk in either order.
        let sane = pricedModel(id: "acme/sane", input: 0.5, output: 2)
        for models in [[junkA, junkB, sane], [sane, junkB, junkA]] {
            let selection = AuxiliaryModelSelector.selection(models: models, sessionModelID: "acme/flagship")
            XCTAssertEqual(selection.modelID, "acme/sane")
            XCTAssertEqual(selection.source, .catalogHeuristic)
        }
    }

    func testZeroOrNegativePriceComponentsAreRejected() {
        let partialZeroInput = pricedModel(id: "acme/zero-input-nano", input: 0, output: 0.1)
        let partialZeroOutput = pricedModel(id: "acme/zero-output-nano", input: 0.1, output: 0)
        let negativeInput = pricedModel(id: "acme/negative-input-nano", input: -0.1, output: 1)
        let negativeOutput = pricedModel(id: "acme/negative-output-nano", input: 1, output: -0.1)
        let priced = pricedModel(id: "acme/priced", input: 0.4, output: 1.2)

        let selection = AuxiliaryModelSelector.selection(
            models: [partialZeroInput, partialZeroOutput, negativeInput, negativeOutput, priced],
            sessionModelID: "acme/flagship"
        )

        XCTAssertEqual(selection.modelID, "acme/priced")
    }

    func testFallsBackToSessionModelWhenCatalogHasNoPrices() {
        let selection = AuxiliaryModelSelector.selection(
            models: TrustedRouterModelCatalog.defaultModels,
            sessionModelID: "tr/prometheus"
        )

        XCTAssertEqual(selection.modelID, TrustedRouterDefaults.prometheusModel)
        XCTAssertEqual(selection.source, .sessionModelFallback)
    }

    func testFallbackCanonicalizesAndDefaultsTheSessionModel() {
        XCTAssertEqual(
            AuxiliaryModelSelector.selection(models: [], sessionModelID: "/prometheus").modelID,
            TrustedRouterDefaults.prometheusModel
        )
        XCTAssertEqual(
            AuxiliaryModelSelector.selection(models: [], sessionModelID: " ").modelID,
            TrustedRouterDefaults.defaultModel
        )
    }

    func testIgnoresUnsuitableCandidates() {
        let embedding = ModelInfo(
            id: "acme/embed-nano",
            provider: "acme",
            displayName: "Embed Nano",
            category: "acme",
            capabilities: ModelCapabilities(
                inputPricePerMillionTokens: 0.01,
                outputPricePerMillionTokens: 0.01,
                outputModalities: ["embedding"]
            )
        )
        let deprecated = ModelInfo(
            id: "acme/legacy-mini",
            provider: "acme",
            displayName: "Legacy Mini",
            category: "acme",
            capabilities: ModelCapabilities(
                inputPricePerMillionTokens: 0.01,
                outputPricePerMillionTokens: 0.01,
                status: "deprecated"
            )
        )
        let zeroPriced = pricedModel(id: "acme/mystery-nano", input: 0, output: 0)

        let selection = AuxiliaryModelSelector.selection(
            models: [embedding, deprecated, zeroPriced, pricedModel(id: "acme/priced", input: 1, output: 4)],
            sessionModelID: "acme/flagship"
        )
        XCTAssertEqual(selection.modelID, "acme/priced")

        let allUnsuitable = AuxiliaryModelSelector.selection(
            models: [embedding, deprecated, zeroPriced],
            sessionModelID: "acme/flagship"
        )
        XCTAssertEqual(allUnsuitable.modelID, "acme/flagship")
        XCTAssertEqual(allUnsuitable.source, .sessionModelFallback)
    }

    func testTieBreakIsDeterministic() {
        let models = [
            pricedModel(id: "acme/twin-b", input: 0.5, output: 1.5),
            pricedModel(id: "acme/twin-a", input: 0.5, output: 1.5)
        ]

        XCTAssertEqual(
            AuxiliaryModelSelector.selection(models: models, sessionModelID: "x").modelID,
            AuxiliaryModelSelector.selection(models: models.reversed(), sessionModelID: "x").modelID
        )
        XCTAssertEqual(
            AuxiliaryModelSelector.selection(models: models, sessionModelID: "x").modelID,
            "acme/twin-a"
        )
    }

    private func pricedModel(id: String, input: Double, output: Double, released: Date? = nil) -> ModelInfo {
        ModelInfo(
            id: id,
            provider: String(id.split(separator: "/").first ?? "acme"),
            displayName: String(id.split(separator: "/").last ?? "model"),
            category: "acme",
            capabilities: ModelCapabilities(
                inputPricePerMillionTokens: input,
                outputPricePerMillionTokens: output,
                outputModalities: ["text"],
                releaseDate: released
            )
        )
    }

    private func days(_ count: Double) -> Date {
        Date(timeIntervalSince1970: count * 86_400)
    }
}
