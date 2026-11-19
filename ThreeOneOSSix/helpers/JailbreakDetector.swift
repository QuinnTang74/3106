import Foundation

/// `_dyld_image_count` / `_dyld_get_image_name` live in `<mach-o/dyld.h>`,
/// which Swift exposes through the MachO module rather than Darwin.
#if canImport(MachO)
import MachO
#endif

/// Detects a jailbroken environment by looking at what is loaded into this
/// process.
///
/// Why this matters for a container-management app: on a jailbroken device the
/// kernel chain is not the only way out of the sandbox, so `hasKernelSandboxAccess()`
/// can report success for reasons unrelated to the exploit — a tweak may have
/// already patched the sandbox. That makes a success verdict meaningless, and a
/// failure verdict actively misleading. Refusing to run the chain there keeps
/// every status the UI shows explainable.
///
/// Detection reads the already-loaded image list rather than probing the
/// filesystem: file existence checks produce false positives on rootless
/// jailbreaks (paths are remapped under `/var/jb`), while an injected dylib is
/// unambiguous evidence.
enum JailbreakDetector {
    /// Matched as substrings against loaded image paths, because rootless
    /// jailbreaks mount the bootstrap somewhere other than `/`.
    static let indicators = [
        "/usr/lib/libsubstitute",   // Substitute
        "/usr/lib/substrate",       // Cydia Substrate
        "ElleKit",                  // ElleKit
        "libhooker",                // libhooker
        "/var/jb/",                 // rootless jailbreak prefix
    ]

    /// Pure: testable without a device or a jailbreak.
    static func isJailbroken(imagePaths: [String]) -> Bool {
        imagePaths.contains { path in
            indicators.contains { path.contains($0) }
        }
    }

    /// Which indicator matched, for the log. Returns nil on a clean process.
    static func matchedIndicator(imagePaths: [String]) -> String? {
        for path in imagePaths {
            if let hit = indicators.first(where: { path.contains($0) }) {
                return hit
            }
        }
        return nil
    }

    static func loadedImagePaths() -> [String] {
        var paths: [String] = []
        let count = _dyld_image_count()
        for index in 0..<count {
            if let name = _dyld_get_image_name(index) {
                paths.append(String(cString: name))
            }
        }
        return paths
    }

    static func isJailbroken() -> Bool {
        isJailbroken(imagePaths: loadedImagePaths())
    }

    /// The refusal rule, as pure logic: only the kernel backend is refused.
    /// bad_query and worse_query go through system APIs whose behaviour a tweak
    /// cannot mask in the same way, so they keep running and their verdict
    /// stays attributable.
    static func refusesKernelChain(isJailbroken: Bool, isKernelBackend: Bool) -> Bool {
        isJailbroken && isKernelBackend
    }

    /// Localization key for the refusal notice. Kept here so the log line and
    /// the status text cannot drift apart.
    static let refusalKey = "{{SECRET_hisgwbph}}"
}