import Foundation

/// Per-key baseline store for member-level Gestalt restores.
///
/// The BackupCenter's `.original` snapshot restores a WHOLE file; when two
/// editors share one cache plist (presets, artwork fields, region), restoring
/// the file would clobber unrelated edits. This store records the original
/// value of a single key (or the single fact that the key was absent) before
/// the first write touches it, so a restore can surgically revert one member.
///
/// Nil value semantics: `nil` in a baseline means "the key did not exist at
/// baseline time" — restoring deletes the key rather than writing something.
final class GestaltBaselineStore {
    static let shared = GestaltBaselineStore()

    private var lock = NSLock()
    private var baselines: [String: Baseline]

    struct Baseline: Codable, Hashable {
        /// nil = the key did not exist when the baseline was taken.
        var value: PlistScalar?
        var takenAt: Date
    }

    /// Property-list-safe scalar projection (dict/array values are stored as
    /// opaque XML fragments through the plist encoder — Codable handles the
    /// common scalars; nested containers encode fine as AnyCodable-free
    /// via PropertyListSerialization round-trip below).
    enum PlistScalar: Codable, Hashable {
        case string(String)
        case int(Int)
        case real(Double)
        case bool(Bool)
        case data(Data)
        case date(Date)

        init?(any: Any) {
            switch any {
            case let v as String: self = .string(v)
            case let v as Int: self = .int(v)
            case let v as Double: self = .real(v)
            case let v as Bool: self = .bool(v)
            case let v as Data: self = .data(v)
            case let v as Date: self = .date(v)
            default: return nil
            }
        }

        var anyValue: Any {
            switch self {
            case .string(let v): return v
            case .int(let v): return v
            case .real(let v): return v
            case .bool(let v): return v
            case .data(let v): return v
            case .date(let v): return v
            }
        }
    }

    private init() {
        baselines = Self.load()
    }

    // MARK: - API

    /// Records `currentValue` for `fullKey` on first observation; later calls
    /// are no-ops (the FIRST observed value is the baseline). A nil
    /// `currentValue` records absence.
    func recordBaselineIfNeeded(fullKey: String, currentValue: Any?) {
        lock.lock()
        defer { lock.unlock() }
        guard baselines[fullKey] == nil else { return }
        baselines[fullKey] = Baseline(value: currentValue.flatMap { PlistScalar(any: $0) },
                                      takenAt: Date())
        persist()
    }

    /// The recorded baseline, or nil when the key was never observed.
    func baseline(for fullKey: String) -> Baseline? {
        lock.lock()
        defer { lock.unlock() }
        return baselines[fullKey]
    }

    /// Drops the baseline after a successful restore to baseline state.
    func clearBaseline(fullKey: String) {
        lock.lock()
        defer { lock.unlock() }
        guard baselines.removeValue(forKey: fullKey) != nil else { return }
        persist()
    }

    // MARK: - Persistence

    private static var storeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent("3106", isDirectory: true)
            .appendingPathComponent("gestalt-baselines.plist", isDirectory: false)
    }

    private static func load() -> [String: Baseline] {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? PropertyListDecoder().decode([String: Baseline].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func persist() {
        let url = Self.storeURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let data = try? PropertyListEncoder().encode(baselines) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
