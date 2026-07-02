import Foundation

/// Defensive extractors for reading untrusted JSON values out of an LSP server's responses.
/// `JSONSerialization` yields `NSNumber`s that bridge unpredictably to `Int`/`Double`, and a
/// hostile or buggy server can put a string where a number belongs — these helpers normalize all of
/// that to `nil` rather than trapping.
enum LSPJSON {
    /// An integer from a value that may be an `Int`, an `NSNumber`, or a numeric `String`.
    static func int(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }
}

/// Converts between filesystem paths and `file://` URIs the way LSP servers expect. LSP requires a
/// properly percent-encoded `file://` URI; `URL(fileURLWithPath:)` handles the encoding, and we undo
/// it on the way back.
enum LSPURI {
    /// A `file://` URI for an absolute filesystem path.
    static func from(path: String) -> String {
        URL(fileURLWithPath: path).absoluteString
    }

    /// The filesystem path for a `file://` URI, or `nil` for a non-file / unparseable URI.
    static func path(from uri: String) -> String? {
        guard let url = URL(string: uri), url.isFileURL else { return nil }
        return url.path
    }
}
