import Foundation

/// Which of the two MobileGestalt region keys the device actually carries.
///
/// iOS 27 introduced `regionInfo` alongside the older `legacyRegionInfo`, and a
/// device carries one or the other — not necessarily both. Writing a key the
/// cache never had makes iOS rebuild the whole MobileGestalt cache at boot, so
/// writes must be restricted to keys that already exist. Reads have the mirror
/// problem: hardcoding either key throws `missingRegionFields` on the devices
/// that carry the other, which is exactly what happened for iOS 27 units.
///
/// Pure dictionary logic, kept free of the plist I/O layer so the "which key"
/// decision can be tested without a device.
enum RegionKeyPolicy {
    /// The region string is stored as `<code>/A`, e.g. `LL/A`.
    static let regionSuffix = "/A"

    /// Which info key exists on this device. The newer key wins when both are
    /// present: it is the one iOS 27 reads, and the legacy key is kept in sync
    /// only for downgrade compatibility.
    static func infoKey(
        in extra: [String: Any],
        regionInfo: String,
        legacyRegionInfo: String
    ) -> String? {
        if extra[regionInfo] != nil { return regionInfo }
        if extra[legacyRegionInfo] != nil { return legacyRegionInfo }
        return nil
    }

    static func regionValue(
        in extra: [String: Any],
        regionInfo: String,
        legacyRegionInfo: String
    ) -> String? {
        guard let key = infoKey(
            in: extra,
            regionInfo: regionInfo,
            legacyRegionInfo: legacyRegionInfo
        ) else { return nil }
        return extra[key] as? String
    }

    static func regionText(for code: String) -> String {
        "\(code)\(regionSuffix)"
    }

    /// Copies whichever `-info` keys the dictionary already carries, plus the
    /// country code. Never adds a key: an invented key trips the boot-time
    /// cache rebuild.
    @discardableResult
    static func apply(
        code: String,
        to extra: inout [String: Any],
        regionCode: String,
        regionInfo: String,
        legacyRegionInfo: String
    ) -> [String] {
        var written: [String] = []
        let text = regionText(for: code)
        if extra[regionInfo] != nil {
            extra[regionInfo] = text
            written.append(regionInfo)
        }
        if extra[legacyRegionInfo] != nil {
            extra[legacyRegionInfo] = text
            written.append(legacyRegionInfo)
        }
        if extra[regionCode] != nil {
            extra[regionCode] = code
            written.append(regionCode)
        }
        return written
    }
}