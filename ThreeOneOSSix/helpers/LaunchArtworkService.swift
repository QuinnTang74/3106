import Foundation
import CoreGraphics

/// Launch-artwork replacement (design inspired by GestaltX v1.0.6's
/// LaunchArtworkStore; independent implementation).
///
/// Target: the app's SpringBoard snapshot cache inside its data container —
/// `Library/SplashBoard/Snapshots/<bundle-id> - {GROUP}/`. Replacing those
/// images changes what the launcher shows before the app draws; the app
/// bundle itself is never touched. Group-suffix variants are enumerated by
/// the `<bundle-id> - ` prefix, never assumed.
enum LaunchArtworkService {

    enum ArtworkError: Error, Equatable {
        case snapshotGroupMissing
        case notEditable
        case noValidImages
        case destinationChanged(String)
        case limitsExceeded(String)
        case imageUnavailable
    }

    struct SnapshotFile: Identifiable, Hashable {
        let path: String
        let name: String
        let width: Int
        let height: Int
        let byteCount: Int64
        var id: String { path }
    }

    struct SnapshotGroup {
        let directoryPath: String
        let files: [SnapshotFile]

        var isEditable: Bool { !files.isEmpty }
        var totalBytes: Int64 { files.reduce(0) { $0 + $1.byteCount } }
    }

    /// GestaltX-parity safety limits: one snapshot file ≤ 20MB, ≤ 16 files,
    /// ≤ 64MB per group.
    static let maxFileBytes: Int64 = 20 * 1_048_576
    static let maxFiles = 16
    static let maxGroupBytes: Int64 = 64 * 1_048_576

    // MARK: - Discovery

    /// Enumerates every snapshot group for the bundle ID under the
    /// container's SplashBoard cache, probing each file's pixel dimensions.
    static func locateSnapshotGroups(containerPath: String, bundleID: String,
                                     fileManager: FileManager = .default) -> [SnapshotGroup] {
        let snapshotsRoot = (containerPath as NSString)
            .appendingPathComponent("Library/SplashBoard/Snapshots")
        guard let names = try? fileManager.contentsOfDirectory(atPath: snapshotsRoot) else {
            return []
        }
        let prefix = "\(bundleID) - "
        var groups: [SnapshotGroup] = []
        for name in names.sorted() where name.hasPrefix(prefix) {
            let dir = (snapshotsRoot as NSString).appendingPathComponent(name)
            groups.append(probeGroup(directoryPath: dir, fileManager: fileManager))
        }
        // Legacy layout without the group suffix: the directory IS the cache.
        if groups.isEmpty {
            let bare = (snapshotsRoot as NSString).appendingPathComponent(bundleID)
            if fileManager.fileExists(atPath: bare) {
                groups.append(probeGroup(directoryPath: bare, fileManager: fileManager))
            }
        }
        return groups
    }

    /// Scans one group directory, keeping only files whose dimensions are
    /// probeable and that sit inside the size limit.
    private static func probeGroup(directoryPath: String,
                                   fileManager: FileManager) -> SnapshotGroup {
        let names = (try? fileManager.contentsOfDirectory(atPath: directoryPath).sorted()) ?? []
        var files: [SnapshotFile] = []
        for name in names {
            let full = (directoryPath as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: full, isDirectory: &isDir),
                  !isDir.boolValue else { continue }
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: full)),
                  let dims = LaunchArtworkRenderer.dimensions(of: data),
                  Int64(data.count) <= maxFileBytes else { continue }
            files.append(SnapshotFile(path: full, name: name,
                                      width: dims.width, height: dims.height,
                                      byteCount: Int64(data.count)))
        }
        return SnapshotGroup(directoryPath: directoryPath, files: files)
    }

    // MARK: - Replacement

    /// Replaces every probeable image in the group with `photo` rendered at
    /// that image's dimensions. Per file: version snapshot → temp write →
    /// CAS against the recorded size → atomic rename; on any failure the
    /// already-written files are restored from their snapshots in reverse
    /// order, then the error rethrows.
    static func replaceAll(with photo: CGImage, in group: SnapshotGroup,
                           token: CancellationToken?,
                           fileManager: FileManager = .default) throws -> Int {
        guard group.isEditable else { throw ArtworkError.notEditable }
        guard group.files.count <= maxFiles else {
            throw ArtworkError.limitsExceeded("too many files: \(group.files.count)")
        }
        guard group.totalBytes <= maxGroupBytes else {
            throw ArtworkError.limitsExceeded("group too large: \(group.totalBytes)")
        }

        var committed: [URL] = []
        do {
            for file in group.files {
                try token?.check()
                let rendered = try LaunchArtworkRenderer.render(photo, width: file.width, height: file.height)
                let png = try LaunchArtworkRenderer.pngData(rendered)

                // Version snapshot before the bytes change (BackupCenter
                // owns retention + restore UI).
                _ = try BackupCenter.shared.createVersionSnapshot(
                    target: URL(fileURLWithPath: file.path),
                    feature: .migration,
                    reason: "launch-artwork"
                )

                let temp = file.path + ".\(UUID().uuidString).3106-partial"
                try png.write(to: URL(fileURLWithPath: temp), options: [.atomic])

                // CAS: the target must still be a regular file of the
                // recorded size (a regenerate-respring between pick and
                // apply invalidates the probe).
                let dict = try? fileManager.attributesOfItem(atPath: file.path)
                let currentSize = (dict?[.size] as? NSNumber)?.int64Value
                guard currentSize == file.byteCount else {
                    try? fileManager.removeItem(atPath: temp)
                    throw ArtworkError.destinationChanged(file.name)
                }
                guard rename(temp, file.path) == 0 else {
                    try? fileManager.removeItem(atPath: temp)
                    throw ArtworkError.destinationChanged(file.name)
                }
                committed.append(URL(fileURLWithPath: file.path))
            }
        } catch {
            // Roll back in reverse commit order.
            for url in committed.reversed() {
                let records = BackupCenter.shared.records(feature: .migration)
                    .filter { $0.targetPath == url.path }
                if let latest = records.first {
                    try? BackupCenter.shared.restore(latest)
                }
            }
            throw error
        }
        ActivityHistory.log(.write, feature: "launch-artwork",
                            "\(committed.count) snapshot images replaced")
        return committed.count
    }

    /// Restores the whole group from BackupCenter version snapshots.
    static func restoreGroup(_ group: SnapshotGroup) -> Int {
        var restored = 0
        for file in group.files {
            let records = BackupCenter.shared.records(feature: .migration)
                .filter { $0.targetPath == file.path }
            if let latest = records.first {
                if (try? BackupCenter.shared.restore(latest)) != nil {
                    restored += 1
                }
            }
        }
        if restored > 0 {
            ActivityHistory.log(.restore, feature: "launch-artwork",
                                "\(restored) snapshot images restored")
        }
        return restored
    }
}
