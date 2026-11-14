import Foundation

/// GestaltX #134: backup metadata is an identity record, not a loose JSON
/// sidecar. Validate its filename and fields before an archive is listed or
/// extracted, while keeping an explicit fallback for legacy archives.
enum BackupMetadataPolicy {
    enum Verdict: Equatable {
        case valid
        case legacy
        case rejected(reason: Reason)
    }

    enum Reason: String, Equatable {
        case invalidSidecarName
        case invalidBundleID
        case futureTimestamp
        case unsafePath
        case emptyBundleID
    }

    static let sidecarSuffix = ".manifest.plist"
    static let legacyManifestName = "BackupManifest.plist"
    static let maxFutureTolerance: TimeInterval = 60

    static func sidecarName(forArchive archiveName: String) -> String {
        (archiveName as NSString).deletingPathExtension + sidecarSuffix
    }

    static func validateSidecarName(archiveName: String, sidecarName: String) -> Verdict {
        guard archiveName.pathExtension.lowercased() == "3106save",
              sidecarName == self.sidecarName(forArchive: archiveName) else {
            return .rejected(reason: .invalidSidecarName)
        }
        return .valid
    }

    static func validateManifest(
        bundleID: String,
        createdAt: Date,
        now: Date = Date()
    ) -> Verdict {
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .rejected(reason: .emptyBundleID) }
        guard isValidBundleID(trimmed) else { return .rejected(reason: .invalidBundleID) }
        guard createdAt.timeIntervalSince(now) <= maxFutureTolerance else {
            return .rejected(reason: .futureTimestamp)
        }
        return .valid
    }

    static func validateArchivePath(_ rawPath: String) -> Verdict {
        guard !rawPath.hasPrefix("/"), !rawPath.contains("\\"),
              !rawPath.contains("\0") else {
            return .rejected(reason: .unsafePath)
        }
        let components = rawPath.split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return .rejected(reason: .unsafePath)
        }
        return .valid
    }

    private static func isValidBundleID(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
            }
        }
    }
}

private extension String {
    var pathExtension: String { (self as NSString).pathExtension }
}
