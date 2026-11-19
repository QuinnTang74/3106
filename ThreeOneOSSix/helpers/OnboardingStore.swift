import Foundation

/// First-launch gate.
///
/// The previous implementation keyed off a fingerprint of
/// `<version>#<executable mtime>`. Because every overwrite install rewrites the
/// executable, that token changed on installs that only bumped the build —
/// so an overwrite install of the *same* version replayed the onboarding
/// screen. `currentVersion` already carries the build number ("3.2.6 (25)"),
/// so a genuine upgrade is detectable without the mtime fallback. The whole
/// fingerprint scheme is therefore replaced by a single "has completed" flag.
enum OnboardingStore {
    static let completedKey = "onboarding.completed"
    static let legacyVersionKey = "onboarding.completedVersion"
    static let legacyFingerprintKey = "onboarding.completedFingerprint"

    static var currentVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(version) (\(build))"
    }

    /// Pure decision, kept separate so it is testable without UserDefaults.
    static func shouldShow(hasCompleted: Bool) -> Bool { !hasCompleted }

    static func shouldShow() -> Bool {
#if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--skip-onboarding") { return false }
        if ProcessInfo.processInfo.arguments.contains("--reset-onboarding") { return true }
#endif
        return shouldShow(defaults: .standard)
    }

    /// Testable overload: the migration path must be exercised against a
    /// scratch suite rather than the app's real defaults.
    static func shouldShow(defaults: UserDefaults) -> Bool {
        if defaults.bool(forKey: completedKey) { return false }

        // Migration: an install that finished onboarding under the old
        // fingerprint scheme has no `completedKey`. Adopting either legacy key
        // as evidence of completion keeps 3.2.7 upgrades from replaying the
        // screen — which is exactly the bug this rewrite fixes, so getting the
        // migration wrong would reintroduce it for existing users.
        if hasLegacyCompletion(defaults: defaults) {
            defaults.set(true, forKey: completedKey)
            return false
        }
        return true
    }

    static func markCompleted(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: completedKey)
        // Kept in sync so a downgrade to a fingerprint-era build still finds
        // the keys it looks for.
        defaults.set(currentVersion, forKey: legacyVersionKey)
    }

    private static func hasLegacyCompletion(defaults: UserDefaults) -> Bool {
        if let version = defaults.string(forKey: legacyVersionKey), !version.isEmpty { return true }
        if let fingerprint = defaults.string(forKey: legacyFingerprintKey), !fingerprint.isEmpty { return true }
        return false
    }
}