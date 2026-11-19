import Foundation

/// Which of the two MobileGestalt region keys is authoritative.
///
/// `legacyRegionInfo` is actually `RegionInfoFromSysconfig`
/// (`yK+xavymRGZ3xWc1tb8XDg`) — the cache key the system reads. `regionInfo`
/// (`zHeENZu+wbg7PUprwNwBWg`) is a **non-cache key on iOS 27**: older tools
/// injected it, and a device that was ever touched by one can carry both with
/// different values. Reading the non-cache key first therefore showed the old
/// region after a correct write to the sysconfig key.
///
/// Writes still never invent a key: adding `regionInfo` to a cache that does
/// not carry it trips the boot-time cache validation and forces a rebuild.
/// Pure dictionary logic, so the preference can be tested without a device.
enum RegionKeyPolicy {
    /// The region string is stored as `<code>/A`, e.g. `LL/A`.
    static let regionSuffix = "/A"

    /// Which info key is authoritative. `legacyRegionInfo`
    /// (RegionInfoFromSysconfig) wins; `regionInfo` is only a fallback for
    /// caches that predate the sysconfig key.
    static func infoKey(
        in extra: [String: Any],
        regionInfo: String,
        legacyRegionInfo: String
    ) -> String? {
        if extra[legacyRegionInfo] != nil { return legacyRegionInfo }
        if extra[regionInfo] != nil { return regionInfo }
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