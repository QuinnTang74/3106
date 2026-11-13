import Foundation

/// Pure character-level pagination shared by the paginated text reader
/// (PaginatedTextView) and the macOS CLI test harness. No UI dependencies.
enum TextPagination {
    static let charactersPerPage = 6_000

    /// Splits text into pages of at most `pageLimit` characters without any
    /// layout involvement — deterministic and testable.
    static func paginate(_ text: String, pageLimit: Int = TextPagination.charactersPerPage) -> [String] {
        guard pageLimit > 0 else { return text.isEmpty ? [] : [text] }
        guard !text.isEmpty else { return [] }
        let chars = Array(text)
        guard chars.count > pageLimit else { return [text] }
        var pages: [String] = []
        var start = 0
        while start < chars.count {
            let end = min(start + pageLimit, chars.count)
            pages.append(String(chars[start..<end]))
            start = end
        }
        return pages
    }
}
