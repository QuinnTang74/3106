import Foundation

/// GestaltX App Audio Library parity (independent implementation): rules for
/// replacing an app's notification sound with custom audio. UIKit-free so
/// the macOS policy harness can assert every rule.
enum NotificationSoundPolicy {
    enum ValidationError: Error, Equatable {
        case unsupportedExtension
        case tooLarge
        case emptySource
        case targetMissing
        case unsafePath
    }

    static let allowedExtensions: Set<String> = ["aiff", "aif", "caf", "m4a", "wav"]
    static let maximumBytes: Int64 = 20 * 1024 * 1024

    /// The document picker falls back to `.data` because side-loaded builds
    /// sometimes cannot open audio-typed content; the extension check is the
    /// real gate (GestaltX side-load audio-selection fix).
    static func acceptsSourceExtension(_ pathExtension: String) -> Bool {
        allowedExtensions.contains(pathExtension.lowercased())
    }

    static func validateSourceSize(_ bytes: Int64) throws {
        guard bytes > 0 else { throw ValidationError.emptySource }
        guard bytes <= maximumBytes else { throw ValidationError.tooLarge }
    }

    /// The target is a device-absolute path that must stay inside the
    /// selected app's container. Traversal components, backslashes and
    /// relative paths are refused; containment is decided by the container
    /// prefix (raw forms both sides — never resolve symlinks here, the
    /// /var ↔ /private/var mismatch is the cleaner's issue #2 lesson).
    static func validateTargetPath(
        _ targetPath: String, containerRoot: String
    ) throws {
        guard targetPath.hasPrefix("/"),
              !targetPath.contains(".."), !targetPath.contains("\\"),
              !targetPath.contains("\0") else {
            throw ValidationError.unsafePath
        }
        let root = (containerRoot as NSString).standardizingPath
        let target = (targetPath as NSString).standardizingPath
        guard target.hasPrefix(root + "/") || target == root else {
            throw ValidationError.unsafePath
        }
        guard FileManager.default.fileExists(atPath: target) else {
            throw ValidationError.targetMissing
        }
    }
}
