import Foundation

/// Lock-screen footnote (GestaltX v1.0.6 parity): custom text at the bottom
/// of the lock screen, written NOT through MobileGestalt but as the
/// `LockScreenFootnote` key of the ConfigurationProfiles container's
/// SharedDeviceConfiguration.plist. Single-line, ≤256 characters; takes
/// effect after the next lock/unlock (or respring).
///
/// The write goes through the verified pipeline (auto-backup, in-place
/// inode-preserving replacement, read-back verification) — the same family
/// SupervisedModeService uses on the sibling plist in the same container.
enum SystemSettingsService {

    static let containerPath =
        "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles"
    static let plistName = "SharedDeviceConfiguration.plist"
    static let footnoteKey = "LockScreenFootnote"
    static let maxFootnoteLength = 256

    enum SystemSettingsError: Error, Equatable, LocalizedError {
        case unavailable
        case unreadable
        case invalidPlist
        case textTooLong

        var errorDescription: String? {
            switch self {
            case .unavailable: return "systemsettings.error.unavailable"
            case .unreadable: return "systemsettings.error.unreadable"
            case .invalidPlist: return "systemsettings.error.invalid"
            case .textTooLong: return "systemsettings.error.too_long"
            }
        }
    }

    static var plistPath: String {
        (containerPath as NSString).appendingPathComponent(plistName)
    }

    /// Current footnote text; nil when the plist exists but the key does not
    /// (i.e. factory state). `nil` return of currentState means "no custom
    /// text"; a thrown error means the container is unreachable.
    static func currentFootnote() throws -> String? {
        let root = try readRoot()
        return root[footnoteKey] as? String
    }

    /// Writes the footnote (nil clears the key). Text is trimmed to one line
    /// and the 256-character cap; the file itself must already exist — this
    /// service never creates system plists.
    static func apply(_ text: String?) throws {
        guard FileManager.default.fileExists(atPath: plistPath) else {
            throw SystemSettingsError.unavailable
        }
        var root = try readRoot()

        if let text = text {
            // Single-line enforcement: newlines would break the footnote
            // renderer; collapse instead of rejecting so paste input works.
            let singleLine = text
                .replacingOccurrences(of: "\r\n", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard singleLine.count <= maxFootnoteLength else {
                throw SystemSettingsError.textTooLong
            }
            if singleLine.isEmpty {
                root.removeValue(forKey: footnoteKey)
            } else {
                root[footnoteKey] = singleLine
            }
        } else {
            root.removeValue(forKey: footnoteKey)
        }

        let grant = ContainerStore.grantContainerAccess(containerPath)
        defer {
            if grant >= 0 { SandboxAccess.release(grant) }
        }

        let data = try PropertyListSerialization.data(
            fromPropertyList: root, format: .binary, options: 0
        )
        guard (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) != nil else {
            throw SystemSettingsError.invalidPlist
        }
        try VerifiedFileWriter.write(
            data,
            to: URL(fileURLWithPath: plistPath),
            feature: .gestalt,
            reason: "lockscreen-footnote"
        )
        ActivityHistory.log(.write, feature: "system-settings",
                            text == nil ? "LockScreenFootnote cleared" : "LockScreenFootnote set")
        SoundEffects.play(.confirm)
    }

    private static func readRoot() throws -> [String: Any] {
        let grant = ContainerStore.grantContainerAccess(containerPath)
        defer {
            if grant >= 0 { SandboxAccess.release(grant) }
        }
        guard let data = FileManager.default.contents(atPath: plistPath), !data.isEmpty else {
            throw SystemSettingsError.unreadable
        }
        guard let root = try? PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        ) as? [String: Any] else {
            throw SystemSettingsError.invalidPlist
        }
        return root
    }
}
