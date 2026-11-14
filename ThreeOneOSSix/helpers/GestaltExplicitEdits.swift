import Foundation

/// GestaltX #137: a key the user edited explicitly must not be overwritten
/// by a later layout preset. The persisted set lives in Documents/3106 and
/// is intentionally separate from the device Gestalt cache.
enum GestaltExplicitEdits {
    private static let lock = NSLock()
    private static let fileName = "GestaltExplicitEdits.plist"

    private static var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("3106/\(fileName)", isDirectory: false)
    }

    static func record(_ key: String) {
        lock.lock()
        defer { lock.unlock() }
        var keys = loadLocked()
        keys.insert(key)
        saveLocked(keys)
    }

    static func contains(_ key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return loadLocked().contains(key)
    }

    static func keys() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return loadLocked()
    }

    static func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func loadLocked() -> Set<String> {
        guard let data = try? Data(contentsOf: fileURL),
              let values = try? PropertyListDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(values)
    }

    private static func saveLocked(_ keys: Set<String>) {
        guard let data = try? PropertyListEncoder().encode(keys.sorted()) else { return }
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
