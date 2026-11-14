import Foundation

/// Shared identity comparisons for cache UUIDs, bundle IDs and digests.
/// GestaltX #131: UUID letter case must not decide whether two layouts match.
enum IdentityComparator {
    static func caseInsensitiveEqual(_ lhs: String, _ rhs: String) -> Bool {
        lhs.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(
                rhs.trimmingCharacters(in: .whitespacesAndNewlines)
            ) == .orderedSame
    }
}
