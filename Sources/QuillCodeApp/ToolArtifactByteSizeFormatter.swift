import Foundation

enum ToolArtifactByteSizeFormatter {
    static func label(for byteCount: Int) -> String? {
        guard byteCount > 0 else { return nil }
        if byteCount == 1 { return "1 byte" }
        if byteCount < 1_024 { return "\(byteCount) bytes" }
        let kilobytes = Double(byteCount) / 1_024.0
        if kilobytes < 1_024 {
            return "\(formatted(kilobytes)) KB"
        }
        let megabytes = kilobytes / 1_024.0
        return "\(formatted(megabytes)) MB"
    }

    private static func formatted(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded.rounded() == rounded {
            return "\(Int(rounded))"
        }
        return String(format: "%.1f", rounded)
    }
}
