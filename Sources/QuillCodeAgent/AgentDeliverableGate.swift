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
            }
            var name = String(userMessage[fileRange])
            if name.hasPrefix("./") { name.removeFirst(2) }
            if seen.insert(name).inserted, results.count < 6 {
                results.append(name)
            }
        }
        return results
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
