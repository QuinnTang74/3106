import Foundation

/// Supervised Mode toggle (Regitela parity): flips `IsSupervised` in the
/// ConfigurationProfiles container's CloudConfigurationDetails.plist.
/// The write goes through the verified pipeline (auto-backup, in-place
/// inode-preserving replacement, read-back verification).
///
/// Risk note (surfaced in the UI): never use on an MDM-managed device —
/// flipping supervision breaks the management relationship. A setup screen
/// may appear after the next respring or reboot. Quit the Settings app to
/// apply.
enum SupervisedModeService {

    static let containerPath =
        "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles"
    static let plistName = "CloudConfigurationDetails.plist"
    static let supervisedKey = "IsSupervised"

    enum SupervisedError: Error, Equatable, LocalizedError {
        case unavailable
        case unreadable
        case invalidPlist
        case notAConfigurationProfile
        case notFakeResidue

        var errorDescription: String? {
            switch self {
            case .unavailable: return "supervised.error.unavailable"
            case .unreadable: return "supervised.error.unreadable"
            case .invalidPlist: return "supervised.error.invalid"
            case .notAConfigurationProfile: return "supervised.error.not_profile"
            case .notFakeResidue: return "supervised.error.not_residue"
            }
        }
    }

    static var plistPath: String {
        (containerPath as NSString).appendingPathComponent(plistName)
    }

    /// Current supervision state; nil when the plist or key does not exist.
    static func currentState() -> Bool? {
        guard let root = try? readRoot() else { return nil }
        let value = root[supervisedKey] as? NSNumber
        return value?.boolValue
    }

    /// Third-party "fake supervision" audit (Erosion-CN ConfigView parity).
    ///
    /// A file carrying only `IsSupervised` / `OrganizationName` and no MDM
    /// key or certificate chain is residue from an older tool. It is the
    /// combination that can drive Setup Assistant into a 403 loop after an
    /// OTA update, so it is reported separately from a genuine enrollment.
    enum CloudConfigAudit: Equatable {
        case clean
        case genuineMDM(org: String)
        case fakeResidue(org: String)
    }

    private static let genuineMDMKeys = [
        "ConfigurationSource",
        "PostSetupProfileWasInstalled",
        "AwaitDeviceConfigured",
        "CloudConfigurationUIComplete",
        "ConfigurationURL",
        "AnchorCertificates",
        "SupervisorHostCertificates",
    ]

    static func audit() -> CloudConfigAudit {
        guard let root = try? readRoot() else { return .clean }
        let org = root["OrganizationName"] as? String ?? ""
        if genuineMDMKeys.contains(where: { root[$0] != nil }) {
            return .genuineMDM(org: org)
        }
        let keys = Set(root.keys)
        let fakeOnly: Set<String> = [supervisedKey, "OrganizationName"]
        let supervised = (root[supervisedKey] as? NSNumber)?.boolValue == true
        if supervised && keys.subtracting(fakeOnly).isEmpty {
            return .fakeResidue(org: org)
        }
        return .clean
    }

    /// Removes a fake-supervision file after copying it next to the app's
    /// Documents. Refuses to touch a genuine MDM enrollment.
    static func clearFakeSupervision() throws {
        guard case .fakeResidue = audit() else {
            throw SupervisedError.notFakeResidue
        }
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        if let data = FileManager.default.contents(atPath: plistPath) {
            let docs = FileManager.default.urls(
                for: .documentDirectory, in: .userDomainMask
            )[0]
            let backup = docs.appendingPathComponent(
                "CloudConfigurationDetails.backup-\(stamp).plist"
            )
            try? data.write(to: backup, options: .atomic)
        }
        let grant = SandboxAccess.grant(path: containerPath, writable: true)
        defer {
            if grant >= 0 { SandboxAccess.release(grant) }
        }
        try FileManager.default.removeItem(atPath: plistPath)
        ActivityHistory.log(.write, feature: "supervised", "fake supervision residue removed")
    }

    static func apply(_ supervised: Bool) throws {
        guard FileManager.default.fileExists(atPath: plistPath) else {
            throw SupervisedError.unavailable
        }
        var root = try readRoot()
        root[supervisedKey] = NSNumber(value: supervised)

        let directory = containerPath
        let grant = ContainerStore.grantContainerAccess(directory)
        defer {
            if grant >= 0 { SandboxAccess.release(grant) }
        }

        let data = try PropertyListSerialization.data(
            fromPropertyList: root, format: .binary, options: 0
        )
        // Read-back before writing.
        guard (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) != nil else {
            throw SupervisedError.invalidPlist
        }
        try VerifiedFileWriter.write(
            data,
            to: URL(fileURLWithPath: plistPath),
            feature: .gestalt,
            reason: supervised ? "supervised:enable" : "supervised:disable"
        )
        ActivityHistory.log(
            .write,
            feature: "supervised",
            supervised ? "IsSupervised=true" : "IsSupervised=false"
        )
        SoundEffects.play(.confirm)
    }

    private static func readRoot() throws -> [String: Any] {
        let grant = ContainerStore.grantContainerAccess(containerPath)
        defer {
            if grant >= 0 { SandboxAccess.release(grant) }
        }
        guard let data = FileManager.default.contents(atPath: plistPath), !data.isEmpty else {
            throw SupervisedError.unreadable
        }
        guard let root = try? PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        ) as? [String: Any] else {
            throw SupervisedError.invalidPlist
        }
        return root
    }
}
