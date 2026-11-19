import Foundation

/// A region the user can switch to, independent of the Siri AI flow.
///
/// The existing region path is tied to enabling Siri AI: it writes the
/// regulatory model number of a verified machine profile, which changes the
/// device's regulatory filing. Switching sales region does not need that, and
/// conflating the two would silently alter the regulatory declaration. These
/// targets carry only the region triple: country code + region text.
struct RegionTarget: Hashable, Identifiable {
    /// ISO 3166-1 alpha-2, used to derive the localized display name.
    let country: String
    /// Region prefix as stored in MobileGestalt; the full value is `code/A`.
    let code: String

    var id: String { code }

    /// `LL/A`-style value written to the region-info key.
    var regionText: String { "\(code)/A" }

    /// Display name in the *user's* current locale rather than the app
    /// language: region names are conventions users know by heart in their own
    /// system language, and the picker is about geography, not UI language.
    var displayName: String {
        Locale.current.localizedString(forRegionCode: country) ?? country
    }
}

enum RegionTargets {
    /// Ordered by how often each is likely to be wanted, not alphabetically —
    /// the list is long enough that the first screenful matters.
    static let all: [RegionTarget] = [
        .init(country: "US", code: "LL"),
        .init(country: "JP", code: "J"),
        .init(country: "CN", code: "CH"),
        .init(country: "HK", code: "ZP"),
        .init(country: "TW", code: "TA"),
        .init(country: "KR", code: "KH"),
        .init(country: "GB", code: "B"),
        .init(country: "DE", code: "D"),
        .init(country: "FR", code: "FN"),
        .init(country: "CA", code: "C"),
        .init(country: "AU", code: "X"),
        .init(country: "SG", code: "ZA"),
        .init(country: "IN", code: "HN"),
        .init(country: "VN", code: "VN"),
        .init(country: "AE", code: "AE"),
    ]

    /// Matches a stored region text (`LL/A`) back to a target, so the picker
    /// can show the device's current region as the selection. Returns nil for
    /// a region outside this list — the device may well be set to one.
    static func target(forRegionText text: String) -> RegionTarget? {
        let code = text.hasSuffix("/A") ? String(text.dropLast(2)) : text
        return all.first { $0.code == code }
    }

    static func target(country: String) -> RegionTarget? {
        all.first { $0.country == country }
    }
}