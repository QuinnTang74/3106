import Foundation

/// Maps the system's ordered language preference list onto the languages this
/// app actually ships. Kept free of SwiftUI/UIKit so it can be unit-tested
/// without a running app.
///
/// Return values are raw strings rather than `AppLanguage` cases on purpose:
/// `AppLanguage` lives in a file that imports SwiftUI, so referencing it here
/// would make this file unlinkable in the standalone `swiftc` test harness.
/// Callers do `AppLanguage(rawValue:)` once at the boundary.
enum LanguageResolver {
    static let simplifiedChinese = "zh-Hans"
    static let korean = "ko"
    static let vietnamese = "vi"
    static let english = "en"

    /// Closest shipped language for an ordered preference list
    /// (`Locale.preferredLanguages`). English is the documented fallback.
    ///
    /// Iteration order is the caller's order, not the order of the checks
    /// below: `preferredLanguages` puts the user's current system language
    /// first and fallbacks after, so an explicit user preference must beat our
    /// own default ranking. `["en-US", "ko-KR"]` therefore resolves to `en`,
    /// and `["ko-KR", "en-US"]` to `ko`.
    ///
    /// Chinese variants all collapse to Simplified: 3106 ships no Traditional
    /// bundle, so a zh-Hant reader gets more from Simplified than from a
    /// language they cannot read.
    static func resolve(preferred: [String]) -> String {
        for raw in preferred {
            // Region-qualified tags ("zh-Hant-TW") and bare ones ("ko") both
            // reach the same prefix check. Case is normalized because BCP-47
            // tags are case-insensitive and iOS has historically emitted
            // "zh-cn" as well as "zh-CN".
            let language = raw.lowercased()

            if language.hasPrefix("zh") { return simplifiedChinese }
            if language.hasPrefix("ko") { return korean }
            if language.hasPrefix("vi") { return vietnamese }
            if language.hasPrefix("en") { return english }
        }
        return english
    }

    /// Writes the resolved language on first launch only.
    ///
    /// A stored value always wins: the user may have picked a language in
    /// Settings that differs from the system language, and re-deriving it on
    /// every launch would silently undo that choice.
    static func seedIfNeeded(defaults: UserDefaults = .standard,
                             preferred: [String] = Locale.preferredLanguages,
                             storageKey: String = "appLanguage") {
        guard defaults.string(forKey: storageKey) == nil else { return }
        defaults.set(resolve(preferred: preferred), forKey: storageKey)
    }
}