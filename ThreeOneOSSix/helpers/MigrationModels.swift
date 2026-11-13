import Foundation

/// Data model for the dual-app folder migration engine (design inspired by
/// WCMigrate/XChatTransfer; independent implementation, zero copied code).
///
/// "WeChat migration" is not a hardcoded WeChat pathway: the engine moves
/// arbitrary user-selected files/folders between two application containers.
/// WeChat only gets sort priority and a label in the app picker UI.

enum TransferMode: String, Codable, CaseIterable {
    /// Source overwrites the target; target entries the source lacks are removed.
    case replace
    /// Same-name overwrite, target-only entries preserved.
    case merge
    /// Atomic two-way swap via renamex_np(RENAME_SWAP); errors out when the
    /// filesystem cannot swap — never degrades to copy.
    case exchange

    var riskKey: String {
        switch self {
        case .replace: return "risk.migration.replace"
        case .merge: return "risk.migration.merge"
        case .exchange: return "risk.migration.exchange"
        }
    }
}

/// One user-selected transfer unit: a container-relative path on the source
/// and where it should land relative to the target container root. The UI
/// may edit `targetRelativePath` (MappingView) but never outside the root.
struct MigrationMapping: Codable, Identifiable, Hashable {
    let id: UUID
    var sourceRelativePath: String
    var targetRelativePath: String

    init(id: UUID = UUID(), sourceRelativePath: String, targetRelativePath: String? = nil) {
        self.id = id
        self.sourceRelativePath = sourceRelativePath
        self.targetRelativePath = targetRelativePath ?? sourceRelativePath
    }
}

/// Snapshot record of one file or directory inside the selected tree.
struct MigrationFileRecord: Codable, Hashable {
    /// Path relative to the source mapping root.
    var relativePath: String
    var isDirectory: Bool
    var byteCount: Int64
    var inode: UInt64
    var device: UInt64
    var modifiedAt: Date
    /// Files only; computed during copy and re-verified on resume.
    var sha256: String?
}

/// Full plan produced by the engine's prepare phase. Persisted ONCE as
/// plan.json (the file list can be tens of thousands of entries); receipts
/// reference it by id and embed only the summary, keeping per-file checkpoint
/// writes small.
struct MigrationPlan: Codable, Hashable {
    var id: UUID
    var sourceBundleID: String
    var targetBundleID: String
    var sourceContainerPath: String
    var targetContainerPath: String
    var mode: TransferMode
    var mappings: [MigrationMapping]
    var files: [MigrationFileRecord]
    var totalBytes: Int64
    /// Whether prepare snapped a .3106save archive of the target first.
    var preSnapshotTarget: Bool
    var createdAt: Date

    var summary: MigrationPlanSummary {
        MigrationPlanSummary(
            id: id, sourceBundleID: sourceBundleID, targetBundleID: targetBundleID,
            sourceContainerPath: sourceContainerPath, targetContainerPath: targetContainerPath,
            mode: mode, mappings: mappings, totalBytes: totalBytes,
            preSnapshotTarget: preSnapshotTarget, createdAt: createdAt,
            fileCount: files.count
        )
    }
}

/// Receipt-sized projection of a plan (no file list).
struct MigrationPlanSummary: Codable, Hashable {
    var id: UUID
    var sourceBundleID: String
    var targetBundleID: String
    var sourceContainerPath: String
    var targetContainerPath: String
    var mode: TransferMode
    var mappings: [MigrationMapping]
    var totalBytes: Int64
    var preSnapshotTarget: Bool
    var createdAt: Date
    var fileCount: Int
}

struct MigrationReceipt: Codable, Hashable {
    enum State: String, Codable {
        case prepared
        case running
        case interrupted
        case completed
        case failed
    }

    var id: UUID
    var state: State
    var plan: MigrationPlanSummary
    var completedFiles: Int
    var completedBytes: Int64
    /// Tree-scan-order cursor: the last file whose commit was observed.
    var lastCompletedPath: String?
    /// Set before a RENAME_SWAP, cleared after — an interrupted exchange pair
    /// needs a human "did it already swap?" check before resuming.
    var pendingExchange: Bool
    /// Target-relative paths of mappings whose swap already committed.
    /// Resume skips these — RENAME_SWAP is atomic but a re-executed swap
    /// would swap the trees BACK.
    var exchangedMappings: [String]
    var resumable: Bool
    var updatedAt: Date
    var failureReason: String?
}

/// Resume-time verdict after validating a stored receipt against the live
/// containers.
enum ResumeVerdict: Equatable {
    case ready
    case containerMoved(resolvedSource: String, resolvedTarget: String)
    case appMissing(side: String)
    case alreadyCompleted
    case targetChanged(path: String)
    case exchangeNeedsManualCheck
}

/// Pure container-relative path math shared by the engine, resume
/// validation, and the macOS harness. All roots are relative to their
/// container; empty root = the container root itself.
enum MigrationPathMath {

    /// Maps a source-relative path onto the target mapping root.
    static func remap(_ relative: String, from sourceRoot: String, to targetRoot: String) -> String {
        guard !sourceRoot.isEmpty else {
            return targetRoot.isEmpty ? relative : targetRoot + "/" + relative
        }
        guard relative.hasPrefix(sourceRoot + "/") || relative == sourceRoot else {
            return relative
        }
        let remainder = String(relative.dropFirst(sourceRoot.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if targetRoot.isEmpty { return remainder }
        return remainder.isEmpty ? targetRoot : targetRoot + "/" + remainder
    }

    /// Longest-prefix mapping selection so overlapping mappings resolve
    /// correctly. Returns nil when nothing matches.
    static func mapping(for relativePath: String, in mappings: [MigrationMapping]) -> MigrationMapping? {
        mappings
            .filter { relativePath == $0.sourceRelativePath ||
                      relativePath.hasPrefix($0.sourceRelativePath + "/") }
            .max { $0.sourceRelativePath.count < $1.sourceRelativePath.count }
    }

    /// Projects an absolute TARGET-side path back into the source tree's
    /// relative namespace (used by the replace sweep to decide what counts
    /// as "source has it"). `targetRoot` is the absolute mapped root on the
    /// target container; `entryPath` always sits under it (the sweep only
    /// walks that root). The projection strips the absolute root and prepends
    /// the source root — the target mapping path itself is irrelevant here.
    static func projectedSourcePath(entryPath: String, targetRoot: String,
                                    mapping: MigrationMapping) -> String {
        let under = String(entryPath.dropFirst(targetRoot.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if under.isEmpty {
            return mapping.sourceRelativePath
        }
        if mapping.sourceRelativePath.isEmpty {
            return under
        }
        return mapping.sourceRelativePath + "/" + under
    }
}

/// Error surface shared by the engine and its callers (resolver, task center).
enum EngineError: Error, Equatable {
    case containerUnavailable(String)
    case insufficientSpace(needed: Int64)
    case destinationChanged(String)
    case exchangeUnsupported(String)
    case cancelled
}

/// WeChat recognition for picker convenience. Bundle-string heuristic only —
/// never a path assumption. Device-side executable-name matching can extend
/// this later; the policy stays pure so the harness can test it.
enum MigrationWeChatPolicy {
    static func isWeChatBundle(_ bundleID: String) -> Bool {
        let bundle = bundleID.lowercased()
        if bundle == "com.tencent.xin" { return true }
        // Multi-open clones typically carry wechat/weixin in their IDs.
        return bundle.contains("wechat") || bundle.contains("weixin")
    }
}
