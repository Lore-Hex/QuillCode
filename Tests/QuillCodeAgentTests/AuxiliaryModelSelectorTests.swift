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

    func testFallsBackToSessionModelWhenCatalogHasNoPrices() {
        let selection = AuxiliaryModelSelector.selection(
            models: TrustedRouterModelCatalog.defaultModels,
            sessionModelID: "tr/synth"
        )

        XCTAssertEqual(selection.modelID, TrustedRouterDefaults.synthModel)
        XCTAssertEqual(selection.source, .sessionModelFallback)
    }

    func testFallbackCanonicalizesAndDefaultsTheSessionModel() {
        XCTAssertEqual(
            AuxiliaryModelSelector.selection(models: [], sessionModelID: "/fusion").modelID,
            TrustedRouterDefaults.synthModel
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
