import Foundation

/// Enforcement for the "finished without the file" failure (stall shape 5): the task names a file
/// to CREATE ("write recommendation.md", "build index.md"), the model does real work, then ends on
/// a terminal say — sometimes a bare "Done." — with the named deliverable never written. Prompt
/// guidance alone did not close this (fabrication-needs-enforcement lesson); the gate below makes
/// it mechanical: at terminal-say time, every task-named created file must exist under the
/// workspace root, or the model gets a bounded corrective re-prompt to write it.
///
/// Precision comes from two properties rather than clever parsing:
/// - Only filenames governed by a nearby CREATE verb count, and filenames introduced by a
///   source preposition ("from x.csv", "using y.md", "against z.json") never do.
/// - The gate only fires when the file does NOT exist. Named inputs exist by definition, so an
///   extraction false-positive on an input file is inert. The rare miss — a named input that never
///   existed — yields a corrective prompt whose escape hatch ("write what blocked you") produces
///   an honest artifact instead of a silent dead run.
enum AgentDeliverableGate {
    /// Filenames the user message asks the run to CREATE. Order of first appearance, deduped.
    static func requiredDeliverables(in userMessage: String) -> [String] {
        let declaredInputs = declaredRequiredInputs(in: userMessage)
        let pattern = #"""
        (?ix)
        \b(?:write|writes|build|builds|produce|produces|create|creates|generate|generates|
           save|saves|export|exports|make|makes|output|deliver|delivers)\b
        [^.!?\n]{0,90}?
        (?<![\w./-])
        (\.?/?[\w][\w./-]*\.(?:md|markdown|csv|tsv|txt|json|html?|xlsx?|png|jpe?g|pdf|docx|pptx|ya?ml|toml|xml|svg))
        """#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(userMessage.startIndex..., in: userMessage)
        var seen = Set<String>()
        var results: [String] = []
        regex.enumerateMatches(in: userMessage, range: range) { match, _, _ in
            guard let match, match.numberOfRanges > 1,
                  let fileRange = Range(match.range(at: 1), in: userMessage)
            else { return }
            // Reject filenames introduced by a source preposition anywhere between the verb and
            // the filename — "create a summary of report.pdf" names an input, not a deliverable.
            if let fullRange = Range(match.range(at: 0), in: userMessage) {
                let between = userMessage[fullRange.lowerBound..<fileRange.lowerBound].lowercased()
                for preposition in ["from ", " using ", "against ", " of ", "based on ", "reading "] {
                    if between.contains(preposition) { return }
                }
                // Reject NEGATED create verbs — "Do not write forbidden.txt" forbids the file;
                // forcing it into existence would invert the user's instruction.
                let precedingStart = userMessage.index(
                    fullRange.lowerBound,
                    offsetBy: -24,
                    limitedBy: userMessage.startIndex
                ) ?? userMessage.startIndex
                let preceding = userMessage[precedingStart..<fullRange.lowerBound].lowercased()
                for negation in ["do not ", "don't ", "dont ", "never ", "won't ", "not to ", "without ", "avoid "] {
                    if preceding.hasSuffix(negation) || preceding.contains(negation) { return }
                }
            }
            var name = String(userMessage[fileRange])
            if name.hasPrefix("./") { name.removeFirst(2) }
            let normalizedName = AgentArtifactVerificationGate.normalizedPath(name)
            let isDeclaredInput = declaredInputs.contains(where: {
                AgentArtifactVerificationGate.pathsMatch($0, normalizedName)
            })
            let isBareDeclaredInputAlias = !normalizedName.contains("/")
                && declaredInputs.contains(where: {
                    URL(fileURLWithPath: $0).lastPathComponent == normalizedName
                })
            if isDeclaredInput || isBareDeclaredInputAlias { return }
            if seen.insert(name).inserted {
                results.append(name)
            }
        }

        // A later directory-qualified mention commonly refines an earlier bare filename, as in
        // "produce report.csv" followed by "save it to outputs/report.csv". Treating both as
        // separate deliverables forces an unwanted duplicate at the workspace root. Preserve two
        // qualified paths with the same basename because those are explicit distinct locations.
        let qualifiedBasenames = Set(
            results
                .filter { $0.contains("/") }
                .map { ($0 as NSString).lastPathComponent }
        )
        return Array(results.filter { name in
            name.contains("/") || !qualifiedBasenames.contains((name as NSString).lastPathComponent)
        }.prefix(6))
    }

    /// Evaluation and desktop prompts explicitly inventory mapped inputs. A bare source alias in
    /// the original request (for example `leads.csv`) refers to `inputs/leads.csv`; it must not
    /// become a second output merely because an earlier create verb is within the regex window.
    private static func declaredRequiredInputs(in userMessage: String) -> [String] {
        var inputs: [String] = []
        for line in userMessage.split(whereSeparator: \Character.isNewline) {
            let text = String(line)
            guard text.lowercased().contains("required inputs") else { continue }
            for rawPath in AgentRequestTextScanner.backtickQuotedValues(in: text) {
                let path = AgentArtifactVerificationGate.normalizedPath(rawPath)
                guard AgentRequestPathGuard.isSafeWorkspaceRelativePath(path),
                      path.hasPrefix("inputs/"),
                      !inputs.contains(where: {
                          AgentArtifactVerificationGate.pathsMatch($0, path)
                      })
                else { continue }
                inputs.append(path)
            }
        }
        return inputs
    }

    /// The subset of required deliverables that do not exist under `workspaceRoot`.
    static func missingDeliverables(in userMessage: String, workspaceRoot: URL) -> [String] {
        requiredDeliverables(in: userMessage).filter { name in
            !FileManager.default.fileExists(
                atPath: workspaceRoot.appendingPathComponent(name).path
            )
        }
    }

    static func correctionPrompt(missing: [String]) -> String {
        let list = missing.map { "./\($0)" }.joined(separator: ", ")
        return """
        The task requires the following file(s) to exist on disk and they do not: \(list). Do not \
        end the run without them. Create each one now with host.file.write, containing the results \
        of work you have actually done in this conversation — or, if something genuinely blocked \
        you, containing exactly what you did and what blocked you. Then read each file back to \
        confirm it exists before finishing.
        """
    }
}
