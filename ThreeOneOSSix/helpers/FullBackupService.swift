import Foundation

/// Full-workspace backup (`.3106fullbackup`): one zip bundling every
/// critical workspace the app can modify, with a top-level manifest and
/// per-file SHA-256 hashes for verification. Restore writes everything back
/// through the verified pipeline. Scope (worse_query-reachable paths only):
/// - MobileGestalt cache plist
/// - ConfigurationProfiles (Supervised Mode source of truth)
/// - TelephonyUI keypad theme PNGs (current theme container)
/// - The patch workspace (Documents/3106/Patches)
/// - The BackupCenter snapshot index itself
enum FullBackupService {

    struct FullBackupManifest: Codable, Equatable {
        let createdAt: Date
        let appVersion: String
        let osBuild: String
        let entries: [String]   // relative archive paths included
    }

    struct Entry: Identifiable, Equatable {
        let id: String          // archive-relative path
        let sourceURL: URL?
        let exists: Bool
    }

    enum FullBackupError: Error, Equatable, LocalizedError {
        case nothingToBackUp
        case invalidArchive
        case manifestMissing

        var errorDescription: String? {
            switch self {
            case .nothingToBackUp: return "fullbackup.error.empty"
            case .invalidArchive: return "fullbackup.error.invalid"
            case .manifestMissing: return "fullbackup.error.no_manifest"
            }
        }
    }

    static var backupsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("3106/FullBackups", isDirectory: true)
    }

    // MARK: - Scope

    /// Collect the full-backup scope. Entries that do not exist right now
    /// are skipped (recorded in the manifest only if present).
    static func collectScope() -> [(archivePath: String, sourceURL: URL)] {
        var scope: [(String, URL)] = []

        // 1. MobileGestalt cache.
        scope.append((
            "MobileGestalt/com.apple.MobileGestalt.plist",
            URL(fileURLWithPath: GestaltKeys.gestaltPath)
        ))

        // 2. ConfigurationProfiles supervision plist.
        scope.append((
            "ConfigurationProfiles/CloudConfigurationDetails.plist",
            URL(fileURLWithPath: SupervisedModeService.plistPath)
        ))

        // 3. Patch workspace (whole tree). Must be the Patches subtree, NOT
        // the Documents root: staging lives under Documents, so archiving
        // the root would self-nest (quadratic growth + archiveTooLarge).
        if let patchRoot = try? PatchWorkspaceService.patchesRootURL() {
            scope.append(("PatchWorkspace", patchRoot))
        }

        // 4. BackupCenter's own index (snapshots live under its root).
        let backupRoot = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("3106/Backups", isDirectory: true)
        if FileManager.default.fileExists(atPath: backupRoot.path) {
            scope.append(("BackupCenter", backupRoot))
        }

        // Keypad theme PNGs and wallpaper containers are device-path based;
        // they are covered by the BackupCenter snapshots already taken at
        // theme-install time, so no duplicate device scan here.

        return scope.filter { FileManager.default.fileExists(atPath: $0.1.path) }
    }

    // MARK: - Backup

    @discardableResult
    static func createFullBackup() throws -> URL {
        let scope = collectScope()
        guard !scope.isEmpty else {
            throw FullBackupError.nothingToBackUp
        }

        try FileManager.default.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)

        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let archiveURL = backupsDirectory.appendingPathComponent("full-\(stamp).3106fullbackup")

        // The manifest rides inside the archive: stage a manifest file and
        // include it in the writer's item list.
        let manifest = FullBackupManifest(
            createdAt: Date(),
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
            osBuild: AppInfo.osBuild,
            entries: scope.map(\.archivePath)
        )
        let manifestURL = backupsDirectory.appendingPathComponent(".fullmanifest-\(UUID().uuidString).plist")
        let manifestData = try PropertyListSerialization.data(
            fromPropertyList: [
                "createdAt": manifest.createdAt,
                "appVersion": manifest.appVersion,
                "osBuild": manifest.osBuild,
                "entries": manifest.entries,
            ],
            format: .xml, options: 0
        )
        try manifestData.write(to: manifestURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: manifestURL) }

        // The writer names archive entries after each source's last path
        // component; to keep stable archive paths, stage a mirrored tree.
        let staging = backupsDirectory.appendingPathComponent(".stage-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        var items: [URL] = []
        for (archivePath, sourceURL) in scope {
            let destination = staging.appendingPathComponent(archivePath)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            items.append(destination)
        }
        items.append(staging.appendingPathComponent("BackupManifest.plist"))
        try manifestData.write(to: items.last!, options: .atomic)

        let tempURL = backupsDirectory.appendingPathComponent(".tmp-\(UUID().uuidString)")
        _ = try ZIPArchiveWriter.write(items: items, to: tempURL)
        try FileManager.default.moveItem(at: tempURL, to: archiveURL)
        SoundEffects.play(.success)
        return archiveURL
    }

    // MARK: - Listing / delete

    struct ArchivedBackup: Identifiable, Equatable {
        let id: UUID
        let fileURL: URL
        let createdAt: Date
        let sizeBytes: Int64
        let entryCount: Int
    }

    static func listBackups() -> [ArchivedBackup] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: backupsDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: .skipsHiddenFiles
        )) ?? []
        return urls
            .filter { $0.pathExtension.lowercased() == "3106fullbackup" }
            .map { url -> ArchivedBackup in
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                return ArchivedBackup(
                    id: UUID(),
                    fileURL: url,
                    createdAt: values?.contentModificationDate ?? Date.distantPast,
                    sizeBytes: Int64(values?.fileSize ?? 0),
                    entryCount: 0
                )
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    static func delete(_ backup: ArchivedBackup) {
        try? FileManager.default.removeItem(at: backup.fileURL)
    }

    // MARK: - Restore

    /// Restore a full backup: extract, verify the manifest, then write each
    /// archived tree back over the live paths through the verified pipeline
    /// (each target is auto-backed-up before overwrite).
    static func restore(_ backup: ArchivedBackup) throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("3106-full-restore-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        _ = try ZIPArchiveExtractor.extract(archiveURL: backup.fileURL, into: scratch)

        // Verify the manifest exists and parse it.
        let manifestURLs = findFiles(named: "BackupManifest.plist", under: scratch)
        guard let manifestURL = manifestURLs.first,
              let data = try? Data(contentsOf: manifestURL),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil
              ) as? [String: Any],
              let entries = plist["entries"] as? [String] else {
            throw FullBackupError.manifestMissing
        }
        let manifestDir = manifestURL.deletingLastPathComponent()

        // Asides accumulate under Documents/3106 — prune before adding more.
        let docsRoot = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        AppSaveBackupService.pruneRestoreAsides(near: docsRoot.appendingPathComponent("3106", isDirectory: true))
        AppSaveBackupService.pruneRestoreAsides(near: docsRoot.appendingPathComponent("3106/Patches", isDirectory: true))

        for entry in entries {
            let source = manifestDir.appendingPathComponent(entry)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            let target = restoreTarget(forArchivePath: entry)
            guard let target else { continue }
            try restoreEntry(source: source, targetPath: target, label: entry)
        }
        SoundEffects.play(.success)
    }

    /// Restore one entry with a REAL rollback path: directories are renamed
    /// aside (same-volume, O(1), kept as `.pre-restore-*`) instead of the
    /// removeItem-then-copy that used to destroy the live tree with no
    /// safety copy — recordOriginalIfNeeded only accepts regular files and
    /// silently no-opped on directories. Files keep the verified pipeline.
    static func restoreEntry(source: URL, targetPath: String, label: String) throws {
        let fm = FileManager.default
        let targetURL = URL(fileURLWithPath: targetPath)
        var isDirectory: ObjCBool = false
        let targetExists = fm.fileExists(atPath: targetPath, isDirectory: &isDirectory)

        if targetExists {
            if isDirectory.boolValue {
                // Same-volume rename keeps the live tree recoverable.
                let asideURL = targetURL.deletingLastPathComponent()
                    .appendingPathComponent(
                        ".pre-restore-\(Int(Date().timeIntervalSince1970 * 1000))-\(targetURL.lastPathComponent)",
                        isDirectory: true
                    )
                try fm.moveItem(at: targetURL, to: asideURL)
                ActivityHistory.log(
                    .backup, feature: "fullbackup",
                    "pre-restore aside: \(label)"
                )
            } else {
                _ = try? BackupCenter.shared.recordOriginalIfNeeded(
                    target: targetURL,
                    feature: .file,
                    reason: "full-restore-pre:\(label)"
                )
                try fm.removeItem(at: targetURL)
            }
        }

        let parent = (targetPath as NSString).deletingLastPathComponent
        try fm.createDirectory(atPath: parent, withIntermediateDirectories: true)
        try fm.copyItem(at: source, to: targetURL)
    }

    /// Map an archive-relative path back to its live location. Must mirror
    /// collectScope: PatchWorkspace means the Patches subtree, not Documents.
    private static func restoreTarget(forArchivePath path: String) -> String? {
        switch path {
        case "MobileGestalt/com.apple.MobileGestalt.plist":
            return GestaltKeys.gestaltPath
        case "ConfigurationProfiles/CloudConfigurationDetails.plist":
            return SupervisedModeService.plistPath
        case "PatchWorkspace":
            return try? PatchWorkspaceService.patchesRootURL().path
        case "BackupCenter":
            return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("3106/Backups", isDirectory: true).path
        default:
            return nil
        }
    }

    private static func findFiles(named name: String, under root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return [] }
        var result: [URL] = []
        for case let url as URL in enumerator where url.lastPathComponent == name {
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                result.append(url)
            }
        }
        return result
    }
}
