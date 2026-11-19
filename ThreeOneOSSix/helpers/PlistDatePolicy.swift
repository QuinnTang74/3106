import Foundation

/// Rules for plist values that cannot round-trip unchanged.
///
/// Two failure modes this guards, both previously silent:
/// - Date precision: XML plists store `<date>` at whole-second resolution. A
///   value carrying fractional seconds re-parses as a different instant, so
///   the editor would write a value it could never show back. Reject it and
///   say so instead of rounding behind the user's back.
/// - File size: `PropertyListSerialization` happily parses a prefix of a huge
///   file and then writes back only what it parsed, truncating the original.
///   Refuse at the door.
enum PlistDatePolicy {
    /// 64 MB. Binary plists of this size are already pathological for an
    /// on-device editor; past it the parse cost and the truncation risk both
    /// stop being acceptable.
    static let maximumBytes = 64 * 1024 * 1024

    static func truncateToWholeSecond(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }

    static func hasFractionalSeconds(_ date: Date) -> Bool {
        date.timeIntervalSince1970 != date.timeIntervalSince1970.rounded(.down)
    }

    /// True when `text` can be written to `format` without losing precision.
    /// Only XML is lossy; binary plists keep the full double.
    static func canRepresentText(
        _ text: String,
        format: PropertyListSerialization.PropertyListFormat
    ) -> Bool {
        guard format == .xml else { return true }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(".") else { return false }
        // An unparseable string is a different error; let the parser report it.
        guard let date = GestaltValueParser.parseDate(trimmed) else { return true }
        return !hasFractionalSeconds(date)
    }

    static func exceedsSizeLimit(byteCount: Int64) -> Bool {
        byteCount > Int64(maximumBytes)
    }

    static func exceedsSizeLimit(fileAt url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else { return false }
        return exceedsSizeLimit(byteCount: size.int64Value)
    }
}