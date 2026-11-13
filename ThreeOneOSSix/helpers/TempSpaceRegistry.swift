import Foundation

/// Lease-based scratch-space ledger. Every temporary directory/file the app
/// creates under tmp/ registers a lease; expired leases are swept at launch
/// (and on demand), catching orphans from crashes, cancelled imports, and
/// forgotten defer paths. Old modules keep their defer-based cleanup — the
/// registry only adds a safety net, it does not replace per-call cleanup.
enum TempSpaceRegistry {
    enum Retention: String, Codable {
        /// Cleared by the creator in normal flow; the sweep is crash recovery.
        case session
        /// Survives until 24h after creation (import staging the user may
        /// still want to retry).
        case hours24
        /// Survives 7 days (rejected/deferred import offers).
        case days7
    }

    struct Lease: Codable {
        let id: UUID
        let path: String
        let purpose: String
        let createdAt: Date
        let retention: Retention

        func isExpired(now: Date = Date()) -> Bool {
            let limit: TimeInterval
            switch retention {
            case .session: limit = 6 * 3600       // same-session crash recovery
            case .hours24: limit = 24 * 3600
            case .days7: limit = 7 * 24 * 3600
            }
            return now.timeIntervalSince(createdAt) >= limit
        }
    }

    private static var ledgerURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent("3106", isDirectory: true)
            .appendingPathComponent("TempLeases.plist", isDirectory: false)
    }

    // MARK: - API

    /// Registers a lease for `url` and returns it. Registration is best-effort:
    /// a failure to persist the ledger must never break the operation that
    /// owns the scratch space.
    @discardableResult
    static func register(url: URL, retention: Retention, purpose: String) -> Lease {
        let lease = Lease(id: UUID(), path: url.path, purpose: purpose,
                          createdAt: Date(), retention: retention)
        load { leases in
            leases.append(lease)
            // Cap the ledger: drop oldest expired entries first, then oldest
            // overall, so a long-lived install cannot grow it unboundedly.
            if leases.count > 500 {
                let now = Date()
                leases.sort { ($0.isExpired(now: now) ? 0 : 1, $0.createdAt) < ($1.isExpired(now: now) ? 0 : 1, $1.createdAt) }
                leases.removeFirst(leases.count - 500)
            }
        }
        return lease
    }

    /// Normal-flow cleanup: removes the scratch content AND its lease. The
    /// caller keeps its own defer cleanup; release makes the sweep a no-op.
    static func release(_ lease: Lease) {
        try? FileManager.default.removeItem(atPath: lease.path)
        load { leases in
            leases.removeAll { $0.id == lease.id }
        }
    }

    /// Removes only the ledger entry (scratch already moved/renamed elsewhere,
    /// e.g. a staged import that got committed by rename).
    static func forget(_ lease: Lease) {
        load { leases in
            leases.removeAll { $0.id == lease.id }
        }
    }

    /// Sweeps expired leases: removes scratch content whose lease lapsed and
    /// prunes ledger entries for paths that no longer exist. Called at launch
    /// after SandboxAccess.prepare(); safe to call repeatedly.
    static func purgeExpired(now: Date = Date()) {
        var expired: [Lease] = []
        var kept: [Lease] = []
        load { leases in
            for lease in leases {
                if lease.isExpired(now: now) {
                    expired.append(lease)
                } else {
                    kept.append(lease)
                }
            }
        }
        for lease in expired {
            try? FileManager.default.removeItem(atPath: lease.path)
            log("temp: purged expired scratch \(lease.purpose) (\(lease.retention.rawValue))")
        }
        // Also prune entries pointing at vanished scratch (cleaned elsewhere).
        var existing = kept
        existing.removeAll { !FileManager.default.fileExists(atPath: $0.path) }
        if existing.count != kept.count {
            save(existing)
        }
    }

    /// Counts currently registered (non-expired) leases — diagnostics.
    static var activeCount: Int {
        var count = 0
        load { leases in count = leases.count }
        return count
    }

    // MARK: - Ledger IO

    /// Mutates the ledger under a process-wide lock and persists it. The
    /// mutation closure receives the decoded array (or empty on first run).
    private static func load(_ mutate: (inout [Lease]) -> Void) {
        sharedLock.lock()
        defer { sharedLock.unlock() }

        var leases: [Lease] = []
        if let data = try? Data(contentsOf: ledgerURL),
           let decoded = try? PropertyListDecoder().decode([Lease].self, from: data) {
            leases = decoded
        }
        mutate(&leases)
        save(leases)
    }

    private static let sharedLock = NSLock()

    private static func save(_ leases: [Lease]) {
        let dir = ledgerURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? PropertyListEncoder().encode(leases) {
            try? data.write(to: ledgerURL, options: .atomic)
        }
    }
}
