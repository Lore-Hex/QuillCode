import XCTest
import QuillCodeCore
@testable import QuillCodeApp

/// Native ↔ HTML-harness parity for the slash-command registry and the `/model` sub-search
/// (issue #879). The harness diverging from native has repeatedly let E2E pass while the native app
/// was broken, so this suite enumerates BOTH surfaces from source and asserts they agree on:
///   1. the registered command set (`slashCommandDefinitions` usages),
///   2. the `/model` sub-search trigger rule and price formatting,
/// covering behavior, not just a string gate.
final class WorkspaceSlashRegistryHarnessParityTests: XCTestCase {
    // MARK: - Command set parity

    /// The PR sub-catalog is enumerated per-subcommand natively but collapsed to a single `/pr` row
    /// in the harness; `/subagents` and `/env schedule` are native-only local commands the mock
    /// harness does not model. These are long-standing, PRE-EXISTING divergences — every OTHER command
    /// must match one-for-one between the two surfaces so a new registry entry (like the #879 `/model`
    /// and `/skill` rows) can never land on only one side unnoticed.
    private static let nativeOnlyUsages: Set<String> = [
        "/subagents objective | Name: role",
        "/env schedule name when"
    ]
    private static let harnessOnlyUsages: Set<String> = ["/pr"]

    func testHarnessRegistersTheSameSlashCommandUsagesAsNative() throws {
        let native = Set(SlashCommandCatalog.definitions.map(\.usage))
            .filter { !$0.hasPrefix("/pr ") && $0 != "/pr" }
            .subtracting(Self.nativeOnlyUsages)
        let harness = try harnessSlashUsages()
            .subtracting(Self.harnessOnlyUsages)
        XCTAssertEqual(
            harness,
            native,
            "The harness slashCommandDefinitions must register exactly the native SlashCommandCatalog usages "
                + "(excluding the collapsed /pr sub-catalog + documented native-only commands). "
                + "Native-only: \(native.subtracting(harness).sorted()); harness-only: \(harness.subtracting(native).sorted())."
        )
    }

    func testDocumentedDivergencesStayHonest() throws {
        // Guard the allowlist so it can't silently mask a real drift: each listed exception must
        // actually exist on the side it claims (native-only truly native-only, etc.).
        let native = Set(SlashCommandCatalog.definitions.map(\.usage))
        let harness = try harnessSlashUsages()
        for usage in Self.nativeOnlyUsages {
            XCTAssertTrue(native.contains(usage), "\(usage) is listed native-only but is missing from native.")
            XCTAssertFalse(harness.contains(usage), "\(usage) is listed native-only but the harness now has it.")
        }
        for usage in Self.harnessOnlyUsages {
            XCTAssertTrue(harness.contains(usage), "\(usage) is listed harness-only but is missing from the harness.")
        }
    }

    func testModelAndSkillAreRegisteredInBothSurfaces() throws {
        let native = Set(SlashCommandCatalog.definitions.map(\.usage))
        let harness = try harnessSlashUsages()
        for usage in ["/model name", "/skill name"] {
            XCTAssertTrue(native.contains(usage), "Native catalog is missing \(usage).")
            XCTAssertTrue(harness.contains(usage), "Harness catalog is missing \(usage).")
        }
    }

    func testCompactStaysRegisteredAsAOneLineEntry() throws {
        // /compact is the proof that a feature can be a single registry line, not bespoke UI.
        let native = SlashCommandCatalog.definitions.contains { $0.usage == "/compact" }
        XCTAssertTrue(native, "Native catalog should keep /compact as a one-line registry entry.")
        XCTAssertTrue(try harnessSlashUsages().contains("/compact"), "Harness should keep /compact registered.")
    }

    func testHarnessExecutesThreadLifecycleSlashAliases() throws {
        let harness = try harnessSource()
        [
            #"/^\/(duplicate|duplicate-chat|copy-chat)\b/i"#,
            #"/^\/(pin|pin-chat)\b/i"#,
            #"/^\/(unpin|unpin-chat)\b/i"#,
            #"/^\/(clear|clear-chat|reset-chat)\b/i"#,
            #"/^\/(undo|revert|revert-latest|undo-edit)\b/i"#,
            #"/^\/(archive|archive-chat)\b/i"#,
            #"/^\/(unarchive|unarchive-chat)\b/i"#,
            #"/^\/(delete|delete-chat|remove-chat)\b/i"#,
            #"/^\/(fork-last|fork-from-last)\b/i"#,
            #"/^\/(fork-summary|fork-with-summary)\b/i"#,
            #"/^\/(fork-full|fork-full-context)\b/i"#,
            #"/^\/fork\b/i"#
        ].forEach { pattern in
            XCTAssertTrue(
                harness.contains(pattern),
                "Harness slash execution should include \(pattern)."
            )
        }
        XCTAssertTrue(
            harness.contains("runSidebarThreadAction('delete', state.sidebar.selectedThreadID);"),
            "Harness /delete should execute the same selected-thread delete route as the command palette."
        )
        [
            "runCommand('fork-from-last');",
            "runCommand('fork-with-summary');",
            "runCommand('fork-full-context');",
            "Usage: /fork [last|summary|full]"
        ].forEach { expected in
            XCTAssertTrue(harness.contains(expected), "Harness /fork should include \(expected).")
        }
    }

    // MARK: - /model trigger-rule parity

    /// The harness must gate the `/model` sub-search on the same rule as native: a trailing space
    /// after the command word, no newline, command-start only. Drive shared cases through the Swift
    /// core and assert the harness source encodes the identical prefixes and space requirement.
    func testModelSubSearchTriggerRuleMatchesNative() throws {
        // Native behavior (authoritative).
        XCTAssertTrue(SlashModelCatalogSearch.isActive(in: "/model fast"))
        XCTAssertFalse(SlashModelCatalogSearch.isActive(in: "/model"))
        XCTAssertFalse(SlashModelCatalogSearch.isActive(in: "/modelfoo"))
        XCTAssertFalse(SlashModelCatalogSearch.isActive(in: "run /model fast"))
        XCTAssertFalse(SlashModelCatalogSearch.isActive(in: "/model fast\nmore"))

        // The harness encodes the same prefixes and the trailing-space requirement.
        let harness = try harnessSource()
        XCTAssertTrue(harness.contains("const modelCommandPrefixes = ['/model', '/models']"),
                      "Harness must share the /model command prefixes.")
        XCTAssertTrue(harness.contains("const withSpace = prefix + ' '"),
                      "Harness must require a trailing space after the command word (matches native).")
        XCTAssertTrue(harness.contains("if (leading.includes('\\n')) return null"),
                      "Harness must end the sub-search on a newline (matches native).")
    }

    // MARK: - Slash keyword-fallback parity (the /skill Enter-submit fix)

    /// Once the query has whitespace (an argument is being typed), NEITHER surface may keep a command
    /// suggested via the low-weight free-text (detail/title) fallback — otherwise a fully-typed
    /// `/skill code-review` stays suggested and Enter re-accepts the bare `/skill `, blocking submit.
    func testKeywordFallbackIsSuppressedOnceAnArgumentIsTyped() throws {
        // Native behavior (authoritative): a completed invocation of the command's own example
        // yields NO suggestions, so Enter submits it.
        XCTAssertTrue(SlashCommandCatalog.suggestions(for: "/skill code-review").isEmpty)
        // ...but a partial command word still suggests it, and multi-word usages still prefix-match.
        XCTAssertTrue(SlashCommandCatalog.suggestions(for: "/skill").map(\.usage).contains("/skill name"))
        XCTAssertTrue(SlashCommandCatalog.suggestions(for: "/worktree c").map(\.usage).contains("/worktree create path"))

        // The harness encodes the same whitespace guard before the free-text fallback.
        let harness = try harnessSource()
        XCTAssertTrue(harness.contains("if (query.includes(' ')) return null;"),
                      "Harness must suppress the keyword fallback once the query has whitespace (matches native).")
    }

    // MARK: - /model price-formatting parity

    /// The price label the two surfaces render must agree for present / one-sided / missing / zero /
    /// tiny / huge prices. The native side is computed; the harness side is asserted to contain the
    /// same formatting rule (fixed 4-decimals, trailing-zero trim, `$`, `per 1M`, graceful empty).
    func testPriceLabelFormattingMatchesNative() throws {
        XCTAssertEqual(
            ModelCommandPriceLabel.label(for: ModelCapabilities(
                inputPricePerMillionTokens: 0.8,
                outputPricePerMillionTokens: 4
            )),
            "$0.8 in / $4 out per 1M"
        )
        XCTAssertEqual(ModelCommandPriceLabel.label(for: ModelCapabilities()), "")
        XCTAssertEqual(
            ModelCommandPriceLabel.label(for: ModelCapabilities(inputPricePerMillionTokens: 0, outputPricePerMillionTokens: 0)),
            "$0 in / $0 out per 1M"
        )

        let harness = try harnessSource()
        XCTAssertTrue(harness.contains("safe.toFixed(4).replace(/0+$/, '').replace(/\\.$/, '')"),
                      "Harness currency formatter must match native (4-decimal, trailing-zero trim).")
        XCTAssertTrue(harness.contains("in / ${modelCommandCurrency(output)} out per 1M"),
                      "Harness both-price label must match native wording.")
        XCTAssertTrue(harness.contains("return '';"),
                      "Harness must render an empty price label when no price is known (matches native).")
    }

    // MARK: - Harness parsing

    private func harnessSource(filePath: StaticString = #filePath) throws -> String {
        let root = URL(fileURLWithPath: "\(filePath)")
            .deletingLastPathComponent() // QuillCodeAppTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // package root
        return try String(
            contentsOf: root.appendingPathComponent("E2E/harness/index.html"),
            encoding: .utf8
        )
    }

    /// Extract every `usage:` literal from the harness `slashCommandDefinitions` array.
    private func harnessSlashUsages() throws -> Set<String> {
        let harness = try harnessSource()
        guard let declRange = harness.range(of: "const slashCommandDefinitions = [") else {
            XCTFail("Could not find slashCommandDefinitions in the harness")
            return []
        }
        let afterDecl = harness[declRange.upperBound...]
        guard let closeRange = afterDecl.range(of: "\n    ];") else {
            XCTFail("Could not find the end of slashCommandDefinitions")
            return []
        }
        let body = afterDecl[..<closeRange.lowerBound]
        var usages: Set<String> = []
        var remainder = Substring(body)
        // Each entry is `{ usage: '...', ... }`; pull the first single-quoted value after `usage:`.
        while let marker = remainder.range(of: "usage: '") {
            let afterMarker = remainder[marker.upperBound...]
            guard let close = afterMarker.range(of: "'") else { break }
            usages.insert(String(afterMarker[..<close.lowerBound]))
            remainder = afterMarker[close.upperBound...]
        }
        return usages
    }
}
