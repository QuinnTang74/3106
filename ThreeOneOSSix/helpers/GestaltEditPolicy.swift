import Foundation

/// GestaltX #136/#137/#139: field search, explicit-edit precedence and exact
/// plist comparisons share one Foundation-only policy layer so the macOS
/// harness can assert the rules without UIKit or device-side helpers.
enum GestaltEditPolicy {
    struct Field: Equatable {
        let key: String
        let preview: String
    }

    /// One snapshot per reload: filtering recomputes neither preview nor type.
    static func filtered(_ snapshot: [Field], query: String) -> [Field] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return snapshot }
        return snapshot.filter {
            $0.key.lowercased().contains(needle) || $0.preview.lowercased().contains(needle)
        }
    }

    /// Explicit edits win over a layout preset. Absent keys stay write-once
    /// through the existing anti-bounce guard in GestaltPresetEngine.
    static func keysToApply(
        presetKeys: [String],
        explicitEdits: Set<String>
    ) -> [String] {
        presetKeys.filter { !explicitEdits.contains($0) }
    }

    /// Compare CF type identity first so `<true/>` never equals `<integer>1</integer>`.
    static func exactlyEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        switch (lhs, rhs) {
        case let (l as NSNumber, r as NSNumber):
            guard CFGetTypeID(l) == CFGetTypeID(r) else { return false }
            // Integer and Real are both CFNumber; CFGetTypeID alone would
            // treat <integer>1</integer> and <real>1.0</real> as equal.
            if CFGetTypeID(l) != CFBooleanGetTypeID() {
                let lFloat = CFNumberIsFloatType(unsafeBitCast(l, to: CFNumber.self))
                let rFloat = CFNumberIsFloatType(unsafeBitCast(r, to: CFNumber.self))
                guard lFloat == rFloat else { return false }
            }
            return l.isEqual(to: r)
        case let (l as String, r as String): return l == r
        case let (l as Data, r as Data): return l == r
        case let (l as Date, r as Date): return l == r
        case let (l as [Any], r as [Any]):
            guard l.count == r.count else { return false }
            return zip(l, r).allSatisfy { exactlyEqual($0.0, $0.1) }
        case let (l as [String: Any], r as [String: Any]):
            guard l.count == r.count else { return false }
            return l.allSatisfy { key, value in
                guard let other = r[key] else { return false }
                return exactlyEqual(value, other)
            }
        default: return false
        }
    }

    /// A disabled flag keeps its key and type instead of deleting it.
    static func disabledValue(for existing: Any?) -> Any {
        guard let number = existing as? NSNumber else { return NSNumber(value: false) }
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return NSNumber(value: false) }
        if CFNumberIsFloatType(unsafeBitCast(number, to: CFNumber.self)) {
            return NSNumber(value: 0.0)
        }
        return NSNumber(value: 0)
    }
}
