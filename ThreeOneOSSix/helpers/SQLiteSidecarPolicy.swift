import Foundation

/// SQLite keeps uncommitted pages in `<db>-wal` and the shared-memory index in
/// `<db>-shm`. Restoring only the main file leaves the stale `-wal` behind, and
/// SQLite replays that WAL on the next open — the restored database silently
/// reverts to whatever the WAL still holds. Any restore path that overwrites a
/// SQLite file must neutralize both sidecars.
enum SQLiteSidecarPolicy {
    /// SQLite's magic header, including the trailing NUL, is exactly 16 bytes.
    static let header = Data("SQLite format 3\0".utf8)

    static let suffixes = ["-wal", "-shm"]

    /// Pure: lets the header rule be tested without touching the filesystem.
    static func hasSQLiteHeader(_ prefix: Data) -> Bool {
        prefix.count >= header.count && prefix.prefix(header.count) == header
    }

    static func isSQLiteFile(path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        guard let prefix = try? handle.read(upToCount: header.count) else { return false }
        return hasSQLiteHeader(prefix)
    }

    static func sidecars(for path: String) -> [String] {
        suffixes.map { path + $0 }
    }
}