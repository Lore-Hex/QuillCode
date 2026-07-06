import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class SlashModelCatalogSearchTests: XCTestCase {
    // MARK: - Fixtures

    private func categories() -> [ModelCategorySurface] {
        let priced = ModelInfo(
            id: "trustedrouter/fast",
            provider: "trustedrouter",
            displayName: "Nike 1.0",
            category: "Recommended",
            capabilities: ModelCapabilities(
                inputPricePerMillionTokens: 0.8,
                outputPricePerMillionTokens: 4
            )
        )
        let prometheus = ModelInfo(
            id: TrustedRouterDefaults.prometheusModel,
            provider: "trustedrouter",
            displayName: "Prometheus 1.0",
            category: "Recommended",
            capabilities: ModelCapabilities(
                inputPricePerMillionTokens: 1.5,
                outputPricePerMillionTokens: 7.5
            )
        )
        let unpriced = ModelInfo(
            id: "moonshotai/kimi-k2.6",
            provider: "moonshotai",
            displayName: "Kimi K2.6",
            category: "Safety"
        )
        return [
            ModelCategorySurface(
                category: "Recommended",
                models: [
                    ModelOptionSurface(model: priced, selectedModelID: "trustedrouter/fast"),
                    ModelOptionSurface(model: prometheus, selectedModelID: "trustedrouter/fast")
                ]
            ),
            ModelCategorySurface(
                category: "Safety",
                models: [ModelOptionSurface(model: unpriced, selectedModelID: "trustedrouter/fast")]
            )
        ]
    }

    // MARK: - Trigger detection

    func testQueryTriggersOnlyAfterModelSpace() {
        XCTAssertEqual(SlashModelCatalogSearch.query(in: "/model "), "")
        XCTAssertEqual(SlashModelCatalogSearch.query(in: "/model fast"), "fast")
        XCTAssertEqual(SlashModelCatalogSearch.query(in: "  /model prometheus  "), "prometheus")
        XCTAssertEqual(SlashModelCatalogSearch.query(in: "/models kimi"), "kimi")
    }

    func testQueryDoesNotFireWithoutTrailingSpace() {
        // A bare `/model` stays a top-level slash command row, not the sub-search.
        XCTAssertNil(SlashModelCatalogSearch.query(in: "/model"))
        XCTAssertNil(SlashModelCatalogSearch.query(in: "  /model"))
        // A different token that merely starts with the letters is not our command.
        XCTAssertNil(SlashModelCatalogSearch.query(in: "/modelfoo"))
        XCTAssertNil(SlashModelCatalogSearch.query(in: "/modeling the data"))
    }

    func testQueryDoesNotFireMidTextOrMultiline() {
        // Not command-start (mirrors @-mention / slash rule).
        XCTAssertNil(SlashModelCatalogSearch.query(in: "please run /model fast"))
        XCTAssertNil(SlashModelCatalogSearch.query(in: "see path/model here"))
        // A newline means the draft is prose, not a command.
        XCTAssertNil(SlashModelCatalogSearch.query(in: "/model fast\nand then go"))
    }

    func testIsActiveMatchesQueryPresence() {
        XCTAssertTrue(SlashModelCatalogSearch.isActive(in: "/model "))
        XCTAssertTrue(SlashModelCatalogSearch.isActive(in: "/model gpt"))
        XCTAssertFalse(SlashModelCatalogSearch.isActive(in: "/model"))
        XCTAssertFalse(SlashModelCatalogSearch.isActive(in: "hello world"))
    }

    // MARK: - Filter / ranking

    func testEmptyQueryListsCatalogHead() {
        let suggestions = SlashModelCatalogSearch.suggestions(for: "/model ", categories: categories())
        XCTAssertEqual(suggestions.count, 3)
        XCTAssertEqual(suggestions.first?.modelID, "trustedrouter/fast")
    }

    func testInactiveDraftYieldsNoSuggestions() {
        XCTAssertTrue(SlashModelCatalogSearch.suggestions(for: "/model", categories: categories()).isEmpty)
        XCTAssertTrue(SlashModelCatalogSearch.suggestions(for: "hello", categories: categories()).isEmpty)
    }

    func testPrefixMatchOutranksSubstring() {
        let suggestions = SlashModelCatalogSearch.suggestions(for: "/model prom", categories: categories())
        XCTAssertEqual(suggestions.first?.modelID, TrustedRouterDefaults.prometheusModel)
    }

    func testMultiTermSubstringMatch() {
        let suggestions = SlashModelCatalogSearch.suggestions(for: "/model moon kimi", categories: categories())
        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions.first?.modelID, "moonshotai/kimi-k2.6")
    }

    func testNoMatchYieldsEmpty() {
        XCTAssertTrue(SlashModelCatalogSearch.suggestions(for: "/model zzznope", categories: categories()).isEmpty)
    }

    func testEmptyStateCopyOnlyAppearsForActiveModelSearchWithNoMatches() {
        XCTAssertNil(SlashModelCatalogSearch.emptyStateCopy(
            for: "/model",
            categories: categories(),
            catalogSource: .bundled,
            catalogStatusDetail: nil
        ))
        XCTAssertNil(SlashModelCatalogSearch.emptyStateCopy(
            for: "/model fast",
            categories: categories(),
            catalogSource: .bundled,
            catalogStatusDetail: nil
        ))

        let copy = SlashModelCatalogSearch.emptyStateCopy(
            for: "/model zzznope",
            categories: categories(),
            catalogSource: .bundled,
            catalogStatusDetail: "Bundled catalog only."
        )

        XCTAssertEqual(copy?.title, "No bundled model matches")
        XCTAssertTrue(copy?.detail.contains("\"zzznope\"") == true)
        XCTAssertEqual(copy?.footnote, "Bundled catalog only.")
    }

    func testLimitIsRespectedAndBounded() {
        XCTAssertEqual(SlashModelCatalogSearch.suggestions(for: "/model ", categories: categories(), limit: 1).count, 1)
        XCTAssertTrue(SlashModelCatalogSearch.suggestions(for: "/model ", categories: categories(), limit: 0).isEmpty)
        // A negative limit must not crash (clamped to empty).
        XCTAssertTrue(SlashModelCatalogSearch.suggestions(for: "/model ", categories: categories(), limit: -5).isEmpty)
    }

    func testDedupesModelAcrossCategories() {
        let base = categories()
        // Duplicate the "fast" model into a leading Favorites category as the picker surface does.
        let favorite = base[0].models[0]
        let withFavorites = [ModelCategorySurface(category: "Favorites", models: [favorite])] + base
        let suggestions = SlashModelCatalogSearch.suggestions(for: "/model ", categories: withFavorites)
        let fastCount = suggestions.filter { $0.modelID == "trustedrouter/fast" }.count
        XCTAssertEqual(fastCount, 1, "A model must appear at most once in the flat /model popup.")
    }

    // MARK: - Suggestion payload

    func testSuggestionInsertTextRunsTheModelSwitch() {
        let suggestions = SlashModelCatalogSearch.suggestions(for: "/model fast", categories: categories())
        XCTAssertEqual(suggestions.first?.insertText, "/model trustedrouter/fast")
    }

    func testCurrentModelFlagged() {
        let suggestions = SlashModelCatalogSearch.suggestions(for: "/model fast", categories: categories())
        XCTAssertEqual(suggestions.first?.isCurrent, true)
    }

    func testPricePresentAndMissingRenderGracefully() {
        let suggestions = SlashModelCatalogSearch.suggestions(for: "/model ", categories: categories())
        let priced = suggestions.first { $0.modelID == "trustedrouter/fast" }
        let unpriced = suggestions.first { $0.modelID == "moonshotai/kimi-k2.6" }
        XCTAssertEqual(priced?.priceLabel, "$0.8 in / $4 out per 1M")
        XCTAssertEqual(unpriced?.priceLabel, "", "A model without a catalog price must render with an empty price line.")
    }
}

final class ModelCommandPriceLabelTests: XCTestCase {
    func testBothPrices() {
        let capabilities = ModelCapabilities(
            inputPricePerMillionTokens: 3,
            outputPricePerMillionTokens: 15
        )
        XCTAssertEqual(ModelCommandPriceLabel.label(for: capabilities), "$3 in / $15 out per 1M")
    }

    func testInputOnly() {
        let capabilities = ModelCapabilities(inputPricePerMillionTokens: 0.25)
        XCTAssertEqual(ModelCommandPriceLabel.label(for: capabilities), "$0.25 input per 1M")
    }

    func testOutputOnly() {
        let capabilities = ModelCapabilities(outputPricePerMillionTokens: 2)
        XCTAssertEqual(ModelCommandPriceLabel.label(for: capabilities), "$2 output per 1M")
    }

    func testMissingBothIsEmpty() {
        XCTAssertEqual(ModelCommandPriceLabel.label(for: ModelCapabilities()), "")
    }

    func testZeroPriceRendersAsFree() {
        let capabilities = ModelCapabilities(
            inputPricePerMillionTokens: 0,
            outputPricePerMillionTokens: 0
        )
        XCTAssertEqual(ModelCommandPriceLabel.label(for: capabilities), "$0 in / $0 out per 1M")
    }

    func testTinyPriceKeepsPrecision() {
        XCTAssertEqual(ModelCommandPriceLabel.currency(0.0002), "$0.0002")
    }

    func testHugePriceDoesNotCrash() {
        XCTAssertEqual(ModelCommandPriceLabel.currency(1_000_000), "$1000000")
    }

    func testNonFiniteAndNegativeAreSafe() {
        // ModelCapabilities clamps to >= 0, but the formatter guards independently.
        XCTAssertEqual(ModelCommandPriceLabel.currency(-5), "$0")
        XCTAssertEqual(ModelCommandPriceLabel.currency(.nan), "$0")
        XCTAssertEqual(ModelCommandPriceLabel.currency(.infinity), "$0")
    }
}

final class SlashSkillCommandPlannerTests: XCTestCase {
    func testSupportsSkillNames() {
        XCTAssertTrue(SlashSkillCommandPlanner.supports("skill"))
        XCTAssertTrue(SlashSkillCommandPlanner.supports("  SKILL  "))
        XCTAssertFalse(SlashSkillCommandPlanner.supports("skills"))
        XCTAssertFalse(SlashSkillCommandPlanner.supports("model"))
    }

    func testAgentPromptEmbedsBareSkillName() {
        XCTAssertEqual(
            SlashSkillCommandPlanner.agentPrompt(for: "code-review"),
            """
            Load the `code-review` skill now by calling host.skill.load with arguments {"name":"code-review"}, \
            then follow its instructions.
            """
        )
    }

    func testAgentPromptSanitizesPathsAndTakesFirstToken() {
        XCTAssertEqual(SlashSkillCommandPlanner.bareSkillName(from: "../etc/passwd extra"), "etcpasswd")
        XCTAssertEqual(SlashSkillCommandPlanner.bareSkillName(from: "review then run"), "review")
    }

    func testEmptyArgumentHasNoPrompt() {
        XCTAssertNil(SlashSkillCommandPlanner.agentPrompt(for: ""))
        XCTAssertNil(SlashSkillCommandPlanner.agentPrompt(for: "   "))
        XCTAssertNil(SlashSkillCommandPlanner.agentPrompt(for: "/.."))
    }

    func testSlashParserRoutesSkillToRunSkill() {
        XCTAssertEqual(
            SlashCommandParser.parse("/skill code-review"),
            .runSkill("""
            Load the `code-review` skill now by calling host.skill.load with arguments {"name":"code-review"}, \
            then follow its instructions.
            """)
        )
        XCTAssertEqual(SlashCommandParser.parse("/skill"), .invalid(SlashSkillCommandPlanner.usage))
        XCTAssertEqual(SlashCommandParser.parse("/skills"), .workspaceCommand("toggle-extensions"))
    }

    func testSubmissionPlannerConvertsRunSkillToAgentTurn() {
        let plan = WorkspaceComposerSubmissionPlanner.plan(draft: "/skill code-review")
        XCTAssertEqual(
            plan,
            .agent(prompt: """
            Load the `code-review` skill now by calling host.skill.load with arguments {"name":"code-review"}, \
            then follow its instructions.
            """)
        )
    }

    func testSubmissionPlannerKeepsEmptySkillAsSlashUsage() {
        let plan = WorkspaceComposerSubmissionPlanner.plan(draft: "/skill")
        XCTAssertEqual(plan, .slash(command: .invalid(SlashSkillCommandPlanner.usage), originalPrompt: "/skill"))
    }

    // MARK: - MAJOR 2 regression: a COMPLETE `/skill <name>` must not keep the command suggested
    // (which blocked Enter-submit of the command's own documented example).

    func testCompletedSkillInvocationYieldsNoSlashSuggestions() {
        // The bug: `/skill code-review` matched the `/skill name` definition via the DETAIL text
        // ("...for example /skill code-review"), keeping the popup open so Enter re-accepted `/skill `
        // and dropped `code-review`. The score fix suppresses the free-text fallback once the query
        // has whitespace (an argument is being typed), so a fully-typed invocation shows nothing.
        XCTAssertTrue(SlashCommandCatalog.suggestions(for: "/skill code-review").isEmpty)
        XCTAssertTrue(SlashCommandCatalog.suggestions(for: "/skill deep-research").isEmpty)
    }

    func testPartialSkillStillSuggestsTheCommand() {
        // Typing just the command word (no argument) still surfaces the `/skill name` row so it is
        // discoverable and Tab-completable.
        let usages = SlashCommandCatalog.suggestions(for: "/skill").map(\.usage)
        XCTAssertTrue(usages.contains("/skill name"))
    }

    func testMultiWordUsagePrefixStillMatchesWithAnArgumentBeingTyped() {
        // The whitespace guard must not break structural multi-word usages: `/worktree c` (partial,
        // has a space) still prefix-matches `/worktree create path`.
        let usages = SlashCommandCatalog.suggestions(for: "/worktree c").map(\.usage)
        XCTAssertTrue(usages.contains("/worktree create path"))
    }
}
