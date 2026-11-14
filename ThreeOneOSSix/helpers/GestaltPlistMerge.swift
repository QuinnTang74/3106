import Foundation

/// GestaltX #138: a field import is a patch, not a replacement document.
/// The device's current root is authoritative for layout keys; only explicit
/// CacheExtra keys from the import may be overwritten, and no key is removed.
enum GestaltMergeError: Error, Equatable {
    case missingCacheExtra
    case layoutMismatch
    case unsupportedValueType(key: String)
}

enum GestaltPlistMerge {
    struct Result {
        var root: [String: Any]
        var overwritten: [String]
        var skipped: [String]
        var preserved: Int
    }

    static func mergingFieldImport(
        current: [String: Any],
        imported: [String: Any]
    ) throws -> Result {
        guard let currentExtra = current["CacheExtra"] as? [String: Any],
              let importedExtra = imported["CacheExtra"] as? [String: Any] else {
            throw GestaltMergeError.missingCacheExtra
        }
        if let importedUUID = imported["CacheUUID"] as? String,
           let currentUUID = current["CacheUUID"] as? String,
           !IdentityComparator.caseInsensitiveEqual(importedUUID, currentUUID) {
            throw GestaltMergeError.layoutMismatch
        }

        var merged = current
        var extra = currentExtra
        var overwritten: [String] = []
        var skipped: [String] = []

        for (key, value) in importedExtra {
            guard extra[key] != nil else {
                skipped.append(key)
                continue
            }
            guard isSupported(value) else {
                throw GestaltMergeError.unsupportedValueType(key: key)
            }
            extra[key] = value
            overwritten.append(key)
        }

        merged["CacheExtra"] = extra
        return Result(
            root: merged,
            overwritten: overwritten.sorted(),
            skipped: skipped.sorted(),
            preserved: current.count - 1 + currentExtra.count - overwritten.count
        )
    }

    private static func isSupported(_ value: Any) -> Bool {
        value is String || value is NSNumber || value is Date || value is Data
            || value is [Any] || value is [String: Any]
    }
}
