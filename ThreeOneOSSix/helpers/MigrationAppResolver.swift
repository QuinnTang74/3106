import Foundation

/// Dual-container resolution for the migration engine. Thin over the
/// existing single-app primitives: two resolveAppContainerPath calls plus
/// two root grants held for the task's lifetime (the pattern
/// AppSaveBackupService already uses for one root).
enum MigrationAppResolver {

    struct ResolvedPair {
        let sourceBundleID: String
        let targetBundleID: String
        let sourcePath: String
        let targetPath: String
        /// Grant handles to release when the task ends (may be empty when
        /// the backend needs no grants).
        let grants: [Int64]

        func release() {
            for grant in grants where grant >= 0 {
                SandboxAccess.release(grant)
            }
        }
    }

    /// Re-resolves both containers and takes root grants. Callers must
    /// `release()` — the grants MUST stay held for the whole task lifetime
    /// (prepare, validate, run); releasing mid-task makes every subsequent
    /// container read EPERM on device.
    static func resolve(sourceBundleID: String, targetBundleID: String) throws -> ResolvedPair {
        guard let sourcePath = ContainerStore.resolveAppContainerPath(bundleID: sourceBundleID)
            ?? ContainerStore.resolveAppContainerPathByMetadataScan(bundleID: sourceBundleID) else {
            throw EngineError.containerUnavailable("source: \(sourceBundleID)")
        }
        guard let targetPath = ContainerStore.resolveAppContainerPath(bundleID: targetBundleID)
            ?? ContainerStore.resolveAppContainerPathByMetadataScan(bundleID: targetBundleID) else {
            throw EngineError.containerUnavailable("target: \(targetBundleID)")
        }

        var grants: [Int64] = []
        let sourceGrant = ContainerStore.grantContainerAccess(sourcePath)
        if sourceGrant >= 0 { grants.append(sourceGrant) }
        let targetGrant = ContainerStore.grantContainerAccess(targetPath)
        if targetGrant >= 0 { grants.append(targetGrant) }

        return ResolvedPair(sourceBundleID: sourceBundleID, targetBundleID: targetBundleID,
                            sourcePath: sourcePath, targetPath: targetPath,
                            grants: grants)
    }

    // MARK: - WeChat convenience ordering (no hardcoded business paths)

    /// True for WeChat and WeChat-clones. Used ONLY for sort priority and a
    /// picker label — never for path assumptions.
    static func isWeChatFamily(_ app: InstalledApp) -> Bool {
        MigrationWeChatPolicy.isWeChatBundle(app.bundleID)
    }

    /// Sorts app lists for the migration picker: WeChat-family first (stable
    /// within groups), then everything else alphabetically.
    static func sortedForPicker(_ apps: [InstalledApp]) -> [InstalledApp] {
        apps.sorted { lhs, rhs in
            let l = isWeChatFamily(lhs)
            let r = isWeChatFamily(rhs)
            if l != r { return l }
            if l && r { return lhs.bundleID < rhs.bundleID }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }
}
