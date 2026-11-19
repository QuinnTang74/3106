import Foundation

enum ExploitSupportPolicy {
    static let verifiedIOS17Range = "17.0–17.7.x"
    static let verifiedIOS18Range = "18.0–18.7.1"

    /// The iOS 18 release that closed the kernel exploit window.
    ///
    /// Apple fixed CVE-2025-43510 and CVE-2025-43520 — the bugs this project's
    /// kernel chain (DarkSword lineage) depends on — in iOS 18.7.2. Every
    /// later 18.x build is therefore unsupported by design, not by an
    /// oversight in the version table. Kept as a constant so the explanation
    /// shown to users cannot drift from the boundary enforced above.
    static let ios18KernelPatchedAt = "18.7.2"
    static let verifiedIOS26BadQueryRange = "26.0–26.6.1"
    static let verifiedIOS26WorseQueryRange = "26.7–26.7.2"

    /// Every 27.0–27.2 build is accepted unconditionally, so the range must
    /// stop at the minor version — writing "27.2.1" here would claim a patch
    /// boundary that `supportsWorseQuery` does not enforce.
    static let verifiedIOS27Range = "27.0–27.2"

    /// 27.3 is the only 27.x line that is build-gated, so it gets its own
    /// label. Rendering it inside `verifiedIOS27Range` would hide the fact
    /// that the boundary is a build number, not a version number.
    static let verifiedIOS27BuildGatedRange = "27.3 beta 1"

    static func supportsKernelExploit(major: Int, minor: Int, patch: Int) -> Bool {
        guard minor >= 0, patch >= 0 else { return false }

        if major == 17 {
            return minor <= 7
        }

        if major == 18 {
            return minor < 7 || (minor == 7 && patch <= 1)
        }

        return false
    }

    /// bad_query still works on the builds it was verified for; it is kept as
    /// the primary backend there because it also reaches System Data.
    static func supportsBadQuery(major: Int, minor: Int, patch: Int) -> Bool {
        guard major == 26, minor >= 0, patch >= 0 else { return false }
        return minor < 6 || (minor == 6 && patch <= 1)
    }

    /// Builds where worse_query was verified working on 27.3.
    ///
    /// The upstream 3105 line gated every 27.x build through a table like this.
    /// 3106 replaced it with a bare `minor <= 3`, which let 27.3 beta 2 and
    /// later through even though Apple patched worse_query there — WQ Files
    /// reports the patch landing in 27.3 beta 2 (24C5049d) and recommends
    /// staying on beta 1 (24C5037i). A version range alone cannot express
    /// "this specific build was verified"; an unlisted build must be refused,
    /// otherwise the UI shows "activated" while every grant fails.
    static let verifiedIOS27Builds: [String] = [
        "24C5037i"   // iOS 27.3 beta 1 — operator-verified on hardware
    ]

    /// worse_query targets iOS 26.0–26.7.2 and 27.0–27.2 unconditionally.
    /// 27.3 is gated by `verifiedIOS27Builds` because the technique was
    /// patched mid-cycle.
    ///
    /// `build` defaults to an empty string on purpose: an empty build is not
    /// in the whitelist, so any call site that forgets to pass one fails
    /// closed on 27.3 instead of silently approving an unverified build.
    static func supportsWorseQuery(major: Int, minor: Int, patch: Int, build: String = "") -> Bool {
        guard minor >= 0, patch >= 0 else { return false }
        if major == 26 {
            return minor == 7 && patch <= 2
        }
        if major == 27 {
            if minor <= 2 {
                return true
            }
            if minor == 3 {
                // 27.3.0 only: beta 1 is a 27.3.0 build. Without the patch
                // check, a hypothetical 27.3.1 that reused a whitelisted
                // build string would slip through. Build numbers are unique
                // in practice, but the boundary should not depend on that.
                return patch == 0 && verifiedIOS27Builds.contains(build)
            }
        }
        return false
    }

    /// True for iOS 18 builds at or past the patch that closed the kernel
    /// exploit window (18.7.2+). Those are unsupported permanently, so the UI
    /// explains the reason instead of showing a bare "unsupported".
    static func isIOS18KernelPatched(major: Int, minor: Int, patch: Int) -> Bool {
        guard major == 18 else { return false }
        if minor > 7 { return true }
        return minor == 7 && patch >= 2
    }

    /// Every supported combination is enumerated explicitly by the three
    /// probes above. A fourth "experimental tier" used to short-circuit here
    /// but always returned false, which made it read as a live escape hatch
    /// while being dead code. Anything not listed is unsupported, full stop.
    static func isSupported(major: Int, minor: Int, patch: Int, build: String) -> Bool {
        if supportsKernelExploit(major: major, minor: minor, patch: patch) { return true }
        if supportsBadQuery(major: major, minor: minor, patch: patch) { return true }
        if supportsWorseQuery(major: major, minor: minor, patch: patch, build: build) { return true }
        return false
    }
}