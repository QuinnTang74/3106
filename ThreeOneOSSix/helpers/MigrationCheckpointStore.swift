import Foundation

/// Persistence for migration receipts and the orphan-temp journal.
///
/// Layout: Application Support/3106/Migration/<planID>/receipt.json plus
/// journal.json (pending partial-temp names). Receipts are throttled (every
/// 8 files, or 2s, or 64MB) except before destructive steps — exchange and
/// each mapping's first file force a flush. Files live in the app's own
/// sandbox, so scanning for interrupted tasks needs no grants.
enum MigrationCheckpointStore {

    enum StoreError: Error, Equatable {
        case writeFailed(String)
        case readFailed(String)
    }

    struct Journal: Codable {
        var pendingTemps: [String] = []
    }

    // MARK: - Paths

    /// Test seam: when set, all persistence lands here instead of the real
    /// Application Support store. The app never sets it; only the harness.
    nonisolated(unsafe) static var directoryOverride: URL?

    static func baseDirectory() -> URL {
        if let override = directoryOverride { return override }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent("3106", isDirectory: true)
            .appendingPathComponent("Migration", isDirectory: true)
    }

    static func planDirectory(_ planID: UUID) -> URL {
        baseDirectory().appendingPathComponent(planID.uuidString, isDirectory: true)
    }

    // MARK: - Plan IO

    /// Persists the full plan (with the file list) exactly once, at prepare.
    /// Receipts embed only the summary; run/resume reads the plan back by id.
    static func savePlan(_ plan: MigrationPlan) throws {
        let dir = planDirectory(plan.id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(plan)
        try data.write(to: dir.appendingPathComponent("plan.json"), options: [.atomic])
        syncFile(dir.appendingPathComponent("plan.json").path)
    }

    static func loadPlan(planID: UUID) -> MigrationPlan? {
        let url = planDirectory(planID).appendingPathComponent("plan.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(MigrationPlan.self, from: data)
    }

    // MARK: - Receipt IO

    /// Saves a receipt. `force` bypasses throttling (destructive-step guards).
    static func save(_ receipt: MigrationReceipt, force: Bool = false) throws {
        if !force, shouldThrottle(receipt) { return }
        let dir = planDirectory(receipt.id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(receipt)
        try data.write(to: dir.appendingPathComponent("receipt.json"), options: [.atomic])
        syncFile(dir.appendingPathComponent("receipt.json").path)
    }

    /// Throttle state lives on the call site: this recomputes from receipt
    /// counters — cheap and stateless.
    private static func shouldThrottle(_ receipt: MigrationReceipt) -> Bool {
        // Engine passes force at the meaningful points; the default cadence
        // is "every 8 completed files". Bytes/time throttling is applied by
        // the engine, which owns the clock.
        receipt.completedFiles % 8 != 0
    }

    static func loadAll() -> [MigrationReceipt] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(
            at: baseDirectory(), includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]) else { return [] }
        var receipts: [MigrationReceipt] = []
        for dir in dirs.sorted(by: { $0.path < $1.path }) {
            let url = dir.appendingPathComponent("receipt.json")
            guard let data = try? Data(contentsOf: url),
                  let receipt = try? decoder.decode(MigrationReceipt.self, from: data) else { continue }
            receipts.append(receipt)
        }
        return receipts
    }

    static func remove(planID: UUID) {
        try? FileManager.default.removeItem(at: planDirectory(planID))
    }

    // MARK: - Journal (orphan partial temps)

    static func notePendingTemp(planID: UUID, tempName: String) throws {
        var journal = readJournal(planID)
        journal.pendingTemps.append(tempName)
        writeJournal(journal, planID: planID)
    }

    static func clearPendingTemp(planID: UUID, tempName: String) {
        var journal = readJournal(planID)
        journal.pendingTemps.removeAll { $0 == tempName }
        writeJournal(journal, planID: planID)
    }

    /// Empties the journal after resume consumed the orphan list.
    static func clearJournal(planID: UUID) {
        writeJournal(Journal(), planID: planID)
    }

    static func readJournal(_ planID: UUID) -> Journal {
        let url = planDirectory(planID).appendingPathComponent("journal.json")
        guard let data = try? Data(contentsOf: url),
              let journal = try? JSONDecoder().decode(Journal.self, from: data) else {
            return Journal()
        }
        return journal
    }

    private static func writeJournal(_ journal: Journal, planID: UUID) {
        let dir = planDirectory(planID)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(journal) {
            try? data.write(to: dir.appendingPathComponent("journal.json"), options: [.atomic])
            syncFile(dir.appendingPathComponent("journal.json").path)
        }
    }

    /// fsync a file by path — aligns with PatchTransaction's durable-write
    /// discipline (atomic rename + synchronize) for the checkpoint trail.
    private static func syncFile(_ path: String) {
        let fd = open(path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { return }
        defer { close(fd) }
        fsync(fd)
    }
}
