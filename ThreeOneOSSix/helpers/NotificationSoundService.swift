import Foundation
import UniformTypeIdentifiers

/// Notification sound replacement service (GestaltX App Audio Library
/// parity, independent implementation). The list of known notification-sound
/// paths is a user-maintained Documents plist — no pairing or VPN capture
/// dependency. Install goes through FileReplaceService so every replacement
/// has an automatic backup and a restorable record; refresh immediately
/// after install so the list reflects the new state without reopening.
enum NotificationSoundService {

    struct SoundTarget: Codable, Identifiable, Equatable {
        let bundleID: String
        let appName: String
        /// Container-relative path of the notification sound file.
        let relativePath: String

        var id: String { "\(bundleID)|\(relativePath)" }
    }

    struct InstalledSound: Identifiable, Equatable {
        let target: SoundTarget
        let record: FileReplaceService.ReplaceRecord
        var id: UUID { record.id }
    }

    enum ServiceError: Error, Equatable, LocalizedError {
        case invalidTarget
        case unsupportedExtension
        case sourceUnreadable

        var errorDescription: String? {
            switch self {
            case .invalidTarget: return "notification.sound.error.target"
            case .unsupportedExtension: return "notification.sound.error.extension"
            case .sourceUnreadable: return "notification.sound.error.source"
            }
        }
    }

    static let pickerContentTypes: [UTType] = [.data]

    private static let lock = NSLock()
    private static let fileName = "NotificationSoundPaths.plist"

    private static var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("3106/\(fileName)", isDirectory: false)
    }

    // MARK: - Path table

    static func targets() -> [SoundTarget] {
        lock.lock()
        defer { lock.unlock() }
        return loadLocked().sorted {
            ($0.bundleID, $0.relativePath) < ($1.bundleID, $1.relativePath)
        }
    }

    @discardableResult
    static func saveTarget(bundleID: String, appName: String, relativePath: String) -> [SoundTarget] {
        lock.lock()
        defer { lock.unlock() }
        var stored = loadLocked()
        stored.removeAll {
            $0.bundleID == bundleID && $0.relativePath == relativePath
        }
        stored.append(
            SoundTarget(bundleID: bundleID, appName: appName, relativePath: relativePath)
        )
        persistLocked(stored)
        return stored.sorted {
            ($0.bundleID, $0.relativePath) < ($1.bundleID, $1.relativePath)
        }
    }

    static func deleteTarget(id: String) {
        lock.lock()
        defer { lock.unlock() }
        var stored = loadLocked()
        stored.removeAll { "\( $0.bundleID )|\( $0.relativePath )" == id }
        persistLocked(stored)
    }

    // MARK: - Install / restore

    /// Replace the target file with the picked audio. Delegates the actual
    /// write to FileReplaceService: protected-path guard, automatic backup,
    /// persistent record. The caller resolves both device-specific paths —
    /// `absoluteTargetPath` and the owning `containerRoot` — because container
    /// UUIDs differ per device.
    @discardableResult
    static func install(
        target: SoundTarget,
        absoluteTargetPath: String,
        containerRoot: String,
        sourceURL: URL,
        backupRequested: Bool
    ) throws -> FileReplaceService.ReplaceRecord {
        guard !absoluteTargetPath.isEmpty, !containerRoot.isEmpty else {
            throw ServiceError.invalidTarget
        }
        guard NotificationSoundPolicy.acceptsSourceExtension(
            sourceURL.pathExtension
        ) else { throw ServiceError.unsupportedExtension }

        let secured = sourceURL.startAccessingSecurityScopedResource()
        defer { if secured { sourceURL.stopAccessingSecurityScopedResource() } }
        guard let payload = try? Data(contentsOf: sourceURL) else {
            throw ServiceError.sourceUnreadable
        }
        try NotificationSoundPolicy.validateSourceSize(Int64(payload.count))
        try NotificationSoundPolicy.validateTargetPath(
            absoluteTargetPath, containerRoot: containerRoot
        )

        let record = try FileReplaceService.replace(
            targetPath: absoluteTargetPath,
            payload: payload,
            bundleID: target.bundleID,
            appName: target.appName,
            backupRequested: backupRequested
        )
        return record
    }

    /// Recent replacement records for the installed-sounds list, newest first.
    static func installedSounds() -> [InstalledSound] {
        FileReplaceService.loadLog()
            .filter { NotificationSoundPolicy.acceptsSourceExtension(
                ($0.targetPath as NSString).pathExtension
            ) }
            .prefix(50)
            .map { InstalledSound(target: SoundTarget(
                bundleID: $0.bundleID,
                appName: $0.appName,
                relativePath: $0.targetPath
            ), record: $0) }
    }

    // MARK: - Storage

    private static func loadLocked() -> [SoundTarget] {
        guard let data = try? Data(contentsOf: fileURL),
              let values = try? PropertyListDecoder().decode([SoundTarget].self, from: data)
        else { return [] }
        return values
    }

    private static func persistLocked(_ values: [SoundTarget]) {
        guard let data = try? PropertyListEncoder().encode(values) else { return }
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
