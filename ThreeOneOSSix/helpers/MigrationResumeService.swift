import Foundation
import CryptoKit

/// Startup discovery and resume validation for interrupted migrations.
///
/// Device-side resolution (ContainerStore) is injected by the caller; the
/// validation chain itself is pure FileManager logic so the macOS harness
/// can exercise it against synthetic containers.
enum MigrationResumeService {

    enum ValidationDepth {
        case fast    // exists + size
        case deep    // source/target SHA-256 equality
    }

    struct ValidationReport {
        var verdict: ResumeVerdict
        /// Files whose committed content failed the selected depth check.
        var mismatches: [String]
        /// Number of completed files verified (skipped files are not re-checked).
        var verifiedFiles: Int
    }

    // MARK: - Discovery

    /// Receipts worth surfacing: interrupted, or running-but-stale (a .running
    /// receipt in storage means the process died mid-run — live runs only
    /// persist .running at start and .interrupted/completed at the end).
    static func scanInterrupted(now: Date = Date()) -> [MigrationReceipt] {
        MigrationCheckpointStore.loadAll().filter { receipt in
            switch receipt.state {
            case .interrupted:
                return true
            case .running:
                // Consider stale after 5 minutes without an update.
                return now.timeIntervalSince(receipt.updatedAt) > 300
            default:
                return false
            }
        }
    }

    // MARK: - Validation

    /// Full chain: completion check, container-path drift, then content
    /// verification of committed files. `resolvedSource`/`resolvedTarget` are
    /// the live container paths (nil = app/container missing on that side).
    static func validate(_ receipt: MigrationReceipt,
                         resolvedSource: String?, resolvedTarget: String?,
                         depth: ValidationDepth,
                         fileManager: FileManager = .default) -> ValidationReport {
        if receipt.state == .completed {
            return ValidationReport(verdict: .alreadyCompleted, mismatches: [], verifiedFiles: 0)
        }
        if receipt.pendingExchange {
            return ValidationReport(verdict: .exchangeNeedsManualCheck, mismatches: [], verifiedFiles: 0)
        }
        guard let sourcePath = resolvedSource else {
            return ValidationReport(verdict: .appMissing(side: receipt.plan.sourceBundleID), mismatches: [], verifiedFiles: 0)
        }
        guard let targetPath = resolvedTarget else {
            return ValidationReport(verdict: .appMissing(side: receipt.plan.targetBundleID), mismatches: [], verifiedFiles: 0)
        }
        // Container UUIDs are stable per install; a drift means the app was
        // reinstalled between runs — the recorded plan no longer matches.
        if sourcePath != receipt.plan.sourceContainerPath ||
            targetPath != receipt.plan.targetContainerPath {
            return ValidationReport(verdict: .containerMoved(resolvedSource: sourcePath,
                                                             resolvedTarget: targetPath),
                                    mismatches: [], verifiedFiles: 0)
        }

        guard let plan = MigrationCheckpointStore.loadPlan(planID: receipt.id) else {
            return ValidationReport(verdict: .appMissing(side: receipt.plan.sourceBundleID),
                                    mismatches: [], verifiedFiles: 0)
        }
        // A cursor that no longer exists in the plan's scan order means the
        // plan file and receipt disagree — refuse to resume on that basis.
        if let cursor = receipt.lastCompletedPath,
           !plan.files.contains(where: { $0.relativePath == cursor }) {
            return ValidationReport(verdict: .targetChanged(path: cursor),
                                    mismatches: [], verifiedFiles: 0)
        }

        // Verify committed files on the TARGET against the source content.
        let committed = committedFiles(receipt: receipt, plan: plan)
        var mismatches: [String] = []
        var verified = 0
        for record in committed where !record.isDirectory {
            let sourceFullPath = MigrationTreeScanner.joinRoot(sourcePath, record.relativePath)
            let targetFullPath = targetFullPath(record: record, plan: plan, targetPath: targetPath)
            guard fileManager.fileExists(atPath: targetFullPath) else {
                mismatches.append(record.relativePath)
                continue
            }
            let sourceSize = fileSize(sourceFullPath, fileManager: fileManager)
            let targetSize = fileSize(targetFullPath, fileManager: fileManager)
            if sourceSize != record.byteCount || targetSize != record.byteCount {
                mismatches.append(record.relativePath)
                continue
            }
            if case .deep = depth {
                let sourceHash = try? fileHash(sourceFullPath, fileManager: fileManager)
                let targetHash = try? fileHash(targetFullPath, fileManager: fileManager)
                if sourceHash == nil || sourceHash != targetHash {
                    mismatches.append(record.relativePath)
                    continue
                }
            }
            verified += 1
        }
        if !mismatches.isEmpty {
            return ValidationReport(verdict: .targetChanged(path: mismatches.first ?? ""),
                                    mismatches: mismatches, verifiedFiles: verified)
        }
        return ValidationReport(verdict: .ready, mismatches: [], verifiedFiles: verified)
    }

    /// Files at or before the receipt cursor in the plan's scan order. An
    /// unresolvable cursor yields an empty set (validate() separately
    /// refuses such receipts, so this only guards misuse).
    static func committedFiles(receipt: MigrationReceipt, plan: MigrationPlan) -> [MigrationFileRecord] {
        guard let cursor = receipt.lastCompletedPath else { return [] }
        var committed: [MigrationFileRecord] = []
        var found = false
        for record in plan.files {
            committed.append(record)
            if record.relativePath == cursor {
                found = true
                break
            }
        }
        return found ? committed : []
    }

    /// Resolves a committed file's TARGET absolute path via its mapping.
    static func targetFullPath(record: MigrationFileRecord, plan: MigrationPlan, targetPath: String) -> String {
        let mapping = MigrationPathMath.mapping(for: record.relativePath, in: plan.mappings)
            ?? plan.mappings[0]
        let remainder = MigrationPathMath.remap(record.relativePath,
                                                from: mapping.sourceRelativePath,
                                                to: mapping.targetRelativePath)
        return MigrationTreeScanner.joinRoot(targetPath, remainder)
    }

    // MARK: - Primitives

    private static func fileSize(_ path: String, fileManager: FileManager) -> Int64? {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else { return nil }
        let dict = try? fileManager.attributesOfItem(atPath: path)
        return dict?[.size] as? Int64
    }

    static func fileHash(_ path: String, fileManager: FileManager) throws -> String {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 * 1_048_576), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
