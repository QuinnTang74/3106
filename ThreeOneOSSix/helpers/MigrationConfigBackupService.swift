import Foundation

/// Configuration backup packages (design inspired by WCMigrate's
/// PreferencesService/BackupManifest; independent implementation).
///
/// A package is a zip of one app's Library/Preferences tree (optionally
/// plist-only recursive) plus an embedded manifest.json recording per-file
/// hashes so an import can prove the archive is intact before it can be
/// applied to any app. Packages travel through ShareLink/UIActivityViewController
/// (export) and DocumentPicker / .3106cfg onOpenURL (import).
enum MigrationConfigBackupService {

    static let packageExtension = "3106cfg"
    static let manifestName = "manifest.json"

    enum ConfigError: Error, Equatable {
        case emptySelection
        case manifestMissing
        case manifestCorrupt(String)
        case hashMismatch(String)
        case unsupportedFormat(Int)
        case archiveInvalid(String)
    }

    struct FileRecord: Codable, Hashable {
        let path: String
        let bytes: Int64
        let modified: Date
        let sha256: String
    }

    struct Manifest: Codable, Hashable {
        var format: Int = 1
        var sourceBundleID: String
        var sourceAppName: String
        var createdAt: Date
        var plistOnly: Bool
        var files: [FileRecord]
    }

    struct ImportedSet: Identifiable, Hashable {
        let id: UUID
        let manifest: Manifest
        let directoryURL: URL
        let importedAt: Date
    }

    // MARK: - Export

    /// Snapshots `app`'s Library/Preferences (or a recursive plist-only walk)
    /// into a .3106cfg zip under tmp; caller shares and cleans it up
    /// (TempSpaceRegistry lease, session retention).
    static func exportPackage(app: InstalledApp, plistOnly: Bool,
                              token: CancellationToken? = nil) throws -> URL {
        let prefsRoot = (app.containerPath as NSString).appendingPathComponent("Library/Preferences")
        let fm = FileManager.default
        guard fm.fileExists(atPath: prefsRoot) else {
            throw ConfigError.emptySelection
        }

        let grant = ContainerStore.grantContainerAccess(app.containerPath)
        defer {
            if grant >= 0 { SandboxAccess.release(grant) }
        }

        // Stage: copy the tree (plistOnly filters non-plist files) so the zip
        // writer reads a stable snapshot even if the app is live.
        let scratch = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("3106-cfg-export-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        let lease = TempSpaceRegistry.register(url: scratch, retention: .session,
                                               purpose: "config export \(app.bundleID)")

        var records: [FileRecord] = []
        var stagedRoot = scratch.appendingPathComponent("payload", isDirectory: true)
        try fm.createDirectory(at: stagedRoot, withIntermediateDirectories: true)

        if plistOnly {
            try stagePlistTree(from: prefsRoot, into: stagedRoot.path,
                               records: &records, token: token, fm: fm)
        } else {
            try stageTree(from: prefsRoot, into: stagedRoot.path,
                          records: &records, token: token, fm: fm)
        }

        let manifest = Manifest(sourceBundleID: app.bundleID,
                                sourceAppName: app.displayName,
                                createdAt: Date(),
                                plistOnly: plistOnly,
                                files: records)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: scratch.appendingPathComponent(manifestName), options: [.atomic])

        let output = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("3106-\(app.displayName.safeFilename)-config.\(packageExtension)")
        try? fm.removeItem(at: output) // share target name is ours to overwrite
        _ = try ZIPArchiveWriter.write(items: [stagedRoot, scratch.appendingPathComponent(manifestName)],
                                       to: output)
        TempSpaceRegistry.release(lease) // staging done; zip stays for the share sheet
        return output
    }

    // MARK: - Import

    /// Extracts and verifies a picked package into the app sandbox library.
    /// Hash verification runs BEFORE the set is usable — a tampered entry
    /// rejects the whole package.
    static func importPackage(at url: URL) throws -> ImportedSet {
        let fm = FileManager.default
        let staging = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("3106-cfg-import-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        let lease = TempSpaceRegistry.register(url: staging, retention: .session,
                                               purpose: "config import")

        var securityScoped = false
        if url.startAccessingSecurityScopedResource() { securityScoped = true }
        defer {
            if securityScoped { url.stopAccessingSecurityScopedResource() }
        }

        _ = try ZIPArchiveExtractor.extract(archiveURL: url, into: staging)
        TempSpaceRegistry.forget(lease) // extraction moved in; contents live on

        let manifestURL = staging.appendingPathComponent(manifestName)
        guard fm.fileExists(atPath: manifestURL.path) else {
            throw ConfigError.manifestMissing
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let manifest = try? decoder.decode(Manifest.self, from: try Data(contentsOf: manifestURL)) else {
            throw ConfigError.manifestCorrupt("decode failed")
        }
        guard manifest.format == 1 else {
            throw ConfigError.unsupportedFormat(manifest.format)
        }

        let payloadRoot = staging.appendingPathComponent("payload", isDirectory: true)
        for record in manifest.files {
            let path = payloadRoot.appendingPathComponent(record.path)
            guard let data = try? Data(contentsOf: path) else {
                throw ConfigError.hashMismatch(record.path)
            }
            if Int64(data.count) != record.bytes {
                throw ConfigError.hashMismatch(record.path)
            }
            let hex = try MigrationResumeService.fileHash(path.path, fileManager: fm)
            if hex != record.sha256 {
                throw ConfigError.hashMismatch(record.path)
            }
        }

        // Promote staging into the library store.
        let store = configStoreDirectory().appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: store.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: staging, to: store)

        return ImportedSet(id: UUID(), manifest: manifest,
                           directoryURL: store, importedAt: Date())
    }

    /// Lists verified sets currently stored in the sandbox library.
    static func storedSets() -> [ImportedSet] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(
            at: configStoreDirectory(), includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]) else { return [] }
        var sets: [ImportedSet] = []
        for dir in dirs.sorted(by: { $0.path < $1.path }) {
            let manifestURL = dir.appendingPathComponent(manifestName)
            guard let data = try? Data(contentsOf: manifestURL) else { continue }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let manifest = try? decoder.decode(Manifest.self, from: data) else { continue }
            sets.append(ImportedSet(id: UUID(), manifest: manifest,
                                    directoryURL: dir, importedAt: manifest.createdAt))
        }
        return sets
    }

    static func deleteSet(_ set: ImportedSet) {
        try? FileManager.default.removeItem(at: set.directoryURL)
    }

    // MARK: - Apply

    /// Applies a stored set onto an arbitrary app with replace or merge
    /// semantics (same-name overwrite; merge preserves target-only files).
    /// Exchange is meaningless for one-way config application and is refused.
    static func apply(_ set: ImportedSet, to app: InstalledApp,
                      mode: TransferMode, token: CancellationToken? = nil) throws {
        guard mode == .replace || mode == .merge else {
            throw ConfigError.archiveInvalid("exchange not applicable to config sets")
        }
        let fm = FileManager.default
        let payloadRoot = set.directoryURL.appendingPathComponent("payload", isDirectory: true)
        let targetPrefs = (app.containerPath as NSString).appendingPathComponent("Library/Preferences")

        let grant = ContainerStore.grantContainerAccess(app.containerPath)
        defer {
            if grant >= 0 { SandboxAccess.release(grant) }
        }
        try fm.createDirectory(atPath: targetPrefs, withIntermediateDirectories: true, attributes: nil)

        for record in set.manifest.files {
            try token?.check()
            let source = payloadRoot.appendingPathComponent(record.path)
            let destination = (targetPrefs as NSString).appendingPathComponent(record.path)
            let destDir = (destination as NSString).deletingLastPathComponent
            try fm.createDirectory(atPath: destDir, withIntermediateDirectories: true, attributes: nil)

            let existed = fm.fileExists(atPath: destination)
            let data = try Data(contentsOf: source)
            if existed {
                // VerifiedFileWriter semantics: version snapshot, verified
                // in-place write, rollback on failure — free of charge here.
                try VerifiedFileWriter.write(data, to: URL(fileURLWithPath: destination),
                                             feature: .migration, reason: "config-apply")
            } else {
                try data.write(to: URL(fileURLWithPath: destination), options: [.atomic])
            }
        }
        ActivityHistory.log(.write, feature: "config-apply",
                            "\(set.manifest.sourceBundleID) → \(app.bundleID) (\(mode.rawValue)), \(set.manifest.files.count) files")
    }

    // MARK: - Staging helpers

    private static func stageTree(from sourceRoot: String, into stagedRoot: String,
                                  records: inout [FileRecord],
                                  token: CancellationToken?, fm: FileManager) throws {
        let names = (try? fm.contentsOfDirectory(atPath: sourceRoot).sorted()) ?? []
        for name in names {
            try token?.check()
            let source = (sourceRoot as NSString).appendingPathComponent(name)
            let staged = (stagedRoot as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: source, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                try fm.createDirectory(atPath: staged, withIntermediateDirectories: true)
                try stageTree(from: source, into: staged, records: &records, token: token, fm: fm)
            } else {
                try fm.copyItem(atPath: source, toPath: staged)
                records.append(try recordFor(staged, relativeTo: stagedRoot, fm: fm))
            }
        }
    }

    private static func stagePlistTree(from sourceRoot: String, into stagedRoot: String,
                                       records: inout [FileRecord],
                                       token: CancellationToken?, fm: FileManager) throws {
        let names = (try? fm.contentsOfDirectory(atPath: sourceRoot).sorted()) ?? []
        for name in names {
            try token?.check()
            let source = (sourceRoot as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: source, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                let staged = (stagedRoot as NSString).appendingPathComponent(name)
                try fm.createDirectory(atPath: staged, withIntermediateDirectories: true)
                try stagePlistTree(from: source, into: staged, records: &records, token: token, fm: fm)
            } else if name.hasSuffix(".plist") {
                let staged = (stagedRoot as NSString).appendingPathComponent(name)
                try fm.copyItem(atPath: source, toPath: staged)
                records.append(try recordFor(staged, relativeTo: stagedRoot, fm: fm))
            }
        }
    }

    private static func recordFor(_ path: String, relativeTo root: String, fm: FileManager) throws -> FileRecord {
        let dict = try fm.attributesOfItem(atPath: path)
        let bytes = (dict[.size] as? NSNumber)?.int64Value ?? 0
        let modified = (dict[.modificationDate] as? Date) ?? Date()
        let sha256 = try MigrationResumeService.fileHash(path, fileManager: fm)
        return FileRecord(path: String(path.dropFirst(root.count + 1)),
                          bytes: bytes, modified: modified,
                          sha256: sha256)
    }

    static func configStoreDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent("3106", isDirectory: true)
            .appendingPathComponent("Migration", isDirectory: true)
            .appendingPathComponent("Configs", isDirectory: true)
    }
}

extension String {
    /// Share-sheet-safe filename fragment.
    var safeFilename: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let mapped = unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        return String(mapped).isEmpty ? "app" : String(mapped)
    }
}
