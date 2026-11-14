import Foundation

/// Strict plist value parsing for the field editor. GestaltX #132: an
/// ISO8601 date with trailing text must be rejected, not partially parsed.
enum GestaltValueParser {
    static func parseDate(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = ISO8601DateFormatter()
        let optionSets: [ISO8601DateFormatter.Options] = [
            [.withInternetDateTime, .withFractionalSeconds],
            [.withInternetDateTime],
        ]
        for options in optionSets {
            formatter.formatOptions = options
            guard let date = formatter.date(from: trimmed) else { continue }
            // Round-trip rejects partial parses such as "...Zjunk".
            guard formatter.string(from: date) == trimmed else { return nil }
            return date
        }
        return nil
    }

    static func parseData(_ text: String) -> Data? {
        let compact = text.filter { !$0.isWhitespace }
        guard !compact.isEmpty else { return nil }
        return Data(base64Encoded: compact)
    }
}
