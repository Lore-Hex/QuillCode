import Foundation

/// Shared whitespace-classification used by BOTH the hard-deny floor
/// (`StaticSafetyPolicy.collapseWhitespace`) and the permission-rule subject
/// (`PermissionRuleSubject.normalizedCommand`).
///
/// The two normalizers MUST agree on which scalars count as horizontal-foldable vs newline-like vs
/// zero-width, because the safety design depends on one invariant: the floor's normalization is a
/// STRICT SUPERSET of the subject's. Concretely —
///   - both fold every foldable-horizontal scalar to a single ASCII space, and
///   - both strip every zero-width scalar, and
///   - the ONLY divergence is newline-like scalars: the subject preserves them as command
///     separators (so `echo hi\nrm -rf .` never rides an `echo hi` allow) while the floor's
///     aggressive haystack additionally folds them (so `rm -rf\n/` still hits the floor).
/// Because the divergence is one-directional (the floor folds a proper superset of what the subject
/// folds, and treats separators as MORE collapsible, never less), no whitespace re-spelling can
/// match a wildcard allow rule while dodging the floor. Sharing this one classifier — rather than
/// re-deriving the sets in each file — is what keeps that invariant from silently drifting.
///
/// The classifier deliberately covers a superset of any real shell's IFS word-splitting set
/// (space/tab/newline): exotic Unicode whitespace like NBSP (U+00A0), thin space (U+2009), and
/// ideographic space (U+3000) are NOT shell separators, so `rm -rf<NBSP>/` does not currently parse
/// or delete anything — but folding them anyway is defense-in-depth, so the floor stays a superset
/// of any shell's splitting even if IFS or a future shell were to treat them as separators.
enum WhitespaceFolding {
    /// Zero-width scalars carry no visual width and no word-splitting meaning, so they are stripped
    /// outright (tokens on either side join with NO space). Covers ZERO WIDTH SPACE (U+200B),
    /// ZERO WIDTH NON-JOINER (U+200C), ZERO WIDTH JOINER (U+200D), and ZERO WIDTH NO-BREAK SPACE /
    /// BOM (U+FEFF) — none of which `Unicode.Scalar.properties.isWhitespace` reports as whitespace,
    /// so they must be handled explicitly.
    static func isZeroWidth(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x200B, 0x200C, 0x200D, 0xFEFF:
            return true
        default:
            return false
        }
    }

    /// Vertical / line-breaking whitespace: LF, CR, form-feed (U+000C), vertical-tab (U+000B), NEXT
    /// LINE (U+0085), LINE SEPARATOR (U+2028) and PARAGRAPH SEPARATOR (U+2029). These are the
    /// scalars a command normalizer treats as command SEPARATORS — the subject preserves them; the
    /// floor's aggressive haystack folds them. Form-feed and vertical-tab are grouped here (rather
    /// than with horizontal whitespace) so they are treated exactly as the existing code treats a
    /// newline at each call site, keeping the floor a strict superset of the subject.
    static func isNewlineLike(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x000A, 0x000B, 0x000C, 0x000D, 0x0085, 0x2028, 0x2029:
            return true
        default:
            return false
        }
    }

    /// Any horizontal whitespace scalar that should fold to a single ASCII space: ASCII space/tab
    /// plus every other `isWhitespace` scalar (NBSP U+00A0, thin space U+2009, ideographic space
    /// U+3000, en/em quad, hair space, …) that is NOT a newline-like separator. Zero-width scalars
    /// are excluded (they are stripped, not folded).
    static func isFoldableHorizontal(_ scalar: Unicode.Scalar) -> Bool {
        if isNewlineLike(scalar) || isZeroWidth(scalar) {
            return false
        }
        // `properties.isWhitespace` is the Unicode White_Space property — a strict superset of the
        // shell IFS set — and already excludes the zero-width scalars above.
        return scalar.properties.isWhitespace
    }
}
