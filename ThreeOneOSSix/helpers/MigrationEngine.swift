import Foundation

/// The dual-app folder migration engine (design inspired by
/// WCMigrate/XChatTransfer's DirectMigrationService; independent
/// implementation). One actor per task.
///
/// Mode semantics:
/// - replace: copy source over target, then REMOVE target-only entries under
///   the mapped roots (source is authoritative).
/// - merge: copy source over target; target-only entries stay.
/// - exchange: per-mapping atomic RENAME_SWAP of the whole mapped subtree —
///   the file scan is verification/space only, never a per-file copy.
///
/// Files land through temp+SHA-256+CAS+rename; checkpoints are throttled
/// between files and forced before every destructive step.
actor MigrationEngine {

    private var token: CancellationToken?

    // MARK: - Prepare

    /// Resolves both containers, snapshots the mapped source trees, checks
    /// space, persists plan.json, and optionally snaps a .3106save archive of
    /// the target as the coarse rollback anchor. No migration writes happen.
    func prepare(source: InstalledApp, target: InstalledApp,
                 mappings: [MigrationMapping], mode: TransferMode,
                 preSnapshotTarget: Bool) throws -> MigrationPlan {
        guard mappings.contains(where: { !$0.sourceRelativePath.isEmpty }) else {
            throw EngineError.containerUnavailable("no mappings selected")
        }

        let sourcePath = source.containerPath
        let targetPath = target.containerPath
        guard FileManager.default.fileExists(atPath: sourcePath) else {
            throw EngineError.containerUnavailable("source container missing")
        }
        guard FileManager.default.fileExists(atPath: targetPath) else {
            throw EngineError.containerUnavailable("target container missing")
        }

        if preSnapshotTarget {
            _ = try AppSaveBackupService.backup(app: target)
        }

        let scan = try MigrationTreeScanner.scan(containerPath: sourcePath, mappings: mappings)
        let largest = scan.files.filter { !$0.isDirectory }.map(\.byteCount).max() ?? 0
        let needed = MigrationTreeScanner.spaceEstimate(bytesToAdd: scan.totalBytes, largestFile: largest)
        guard enoughSpace(at: targetPath, needed: needed) else {
            throw EngineError.insufficientSpace(needed: needed)
        }

        let plan = MigrationPlan(
            id: UUID(),
            sourceBundleID: source.bundleID,
            targetBundleID: target.bundleID,
            sourceContainerPath: sourcePath,
            targetContainerPath: targetPath,
            mode: mode,
            mappings: mappings,
            files: scan.files,
            totalBytes: scan.totalBytes,
            preSnapshotTarget: preSnapshotTarget,
            createdAt: Date()
        )
        try MigrationCheckpointStore.savePlan(plan)
        return plan
    }

    // MARK: - Run

    /// Executes the plan. `onProgress` receives throttled receipt snapshots
    /// for UI/ETA. Resume passes prior progress; files already committed are
    /// skipped by the scan-order cursor (no byte-level resume).
    @discardableResult
    func run(plan: MigrationPlan,
             resumeState: MigrationReceipt? = nil,
             token: CancellationToken,
             onProgress: @escaping @Sendable (MigrationReceipt) -> Void) async throws -> MigrationReceipt {
        self.token = token

        var receipt: MigrationReceipt
        if let resume = resumeState {
            receipt = resume
            receipt.state = .running
            receipt.resumable = false
            receipt.failureReason = nil
        } else {
            receipt = MigrationReceipt(
                id: plan.id, state: .running, plan: plan.summary,
                completedFiles: 0, completedBytes: 0,
                lastCompletedPath: nil, pendingExchange: false,
                exchangedMappings: [],
                resumable: true, updatedAt: Date(), failureReason: nil
            )
        }
        try MigrationCheckpointStore.save(receipt, force: true)
        onProgress(receipt)

        if resumeState != nil {
            cleanOrphanTemps(plan: plan)
        }

        let fm = FileManager.default
        // Skip already-committed files only when a cursor exists; a fresh
        // receipt persisted as .running has none and must not skip anything.
        var skipping = resumeState?.lastCompletedPath != nil
        var timeMark = Date()
        var byteMark = receipt.completedBytes
        var fileMark = receipt.completedFiles

        // Pass 1 — per-file work for replace/merge. Exchange skips copying
        // entirely: the swap is atomic per mapping, file-level writes would
        // be pointless (and would corrupt the "both sides intact" invariant).
        if plan.mode != .exchange {
            for record in plan.files {
                try token.check()

                if skipping {
                    if record.relativePath == resumeState?.lastCompletedPath {
                        skipping = false
                    }
                    continue
                }

                if record.isDirectory {
                    try handleDirectory(record, plan: plan, fm: fm)
                } else {
                    try copyOne(record, plan: plan, fm: fm)
                }

                receipt.completedFiles += 1
                receipt.completedBytes += record.isDirectory ? 0 : record.byteCount
                receipt.lastCompletedPath = record.relativePath
                receipt.updatedAt = Date()

                let due = receipt.completedFiles - fileMark >= 8
                    || receipt.completedBytes - byteMark >= 64 * 1_048_576
                    || Date().timeIntervalSince(timeMark) >= 2.0
                if due {
                    try MigrationCheckpointStore.save(receipt)
                    timeMark = Date()
                    byteMark = receipt.completedBytes
                    fileMark = receipt.completedFiles
                    onProgress(receipt)
                }
            }

            // replace: sweep target-only entries under mapped roots now that
            // source content has fully landed. Target-only = exists on target
            // relative tree but not in the source scan.
            if plan.mode == .replace {
                try sweepTargetOnly(plan: plan, fm: fm)
            }
        }

        // Pass 2 — exchange swaps, one atomic RENAME_SWAP per mapping.
        // Mappings already committed before an interruption are skipped:
        // re-executing a swap would swap the trees BACK.
        if plan.mode == .exchange {
            let alreadySwapped = Set(resumeState?.exchangedMappings ?? [])
            for mapping in plan.mappings {
                try token.check()
                guard !alreadySwapped.contains(mapping.targetRelativePath) else {
                    continue
                }
                receipt.pendingExchange = true
                receipt.updatedAt = Date()
                try MigrationCheckpointStore.save(receipt, force: true)

                let sourcePath = MigrationTreeScanner.joinRoot(plan.sourceContainerPath, mapping.sourceRelativePath)
                let targetPath = MigrationTreeScanner.joinRoot(plan.targetContainerPath, mapping.targetRelativePath)
                do {
                    try MigrationFileCopy.swapPaths(sourcePath, targetPath)
                } catch let error as MigrationFileCopy.CopyError {
                    if case .swapUnsupported = error {
                        receipt.pendingExchange = false
                        receipt.state = .failed
                        receipt.failureReason = "exchange unsupported on this volume"
                        receipt.updatedAt = Date()
                        try? MigrationCheckpointStore.save(receipt, force: true)
                        throw EngineError.exchangeUnsupported("RENAME_SWAP unavailable")
                    }
                    throw error
                }

                receipt.pendingExchange = false
                receipt.exchangedMappings.append(mapping.targetRelativePath)
                receipt.updatedAt = Date()
                try MigrationCheckpointStore.save(receipt, force: true)
                onProgress(receipt)
            }
        }

        receipt.state = .completed
        receipt.resumable = false
        receipt.pendingExchange = false
        receipt.updatedAt = Date()
        try MigrationCheckpointStore.save(receipt, force: true)
        onProgress(receipt)
        return receipt
    }

    /// Marks a running receipt interrupted after a cancellation or background
    /// expiration so the next launch offers "check and continue".
    func markInterrupted(_ receipt: MigrationReceipt, reason: String) {
        var updated = receipt
        updated.state = .interrupted
        updated.resumable = true
        updated.failureReason = reason
        updated.updatedAt = Date()
        try? MigrationCheckpointStore.save(updated, force: true)
    }

    // MARK: - Per-entry handlers

    private func copyOne(_ record: MigrationFileRecord, plan: MigrationPlan, fm: FileManager) throws {
        guard let token = token else { throw EngineError.cancelled }

        let mapping = mapping(for: record.relativePath, plan: plan)
        let sourcePath = MigrationTreeScanner.joinRoot(plan.sourceContainerPath, record.relativePath)
        let targetRelative = remapRelative(record.relativePath, from: mapping.sourceRelativePath,
                                           to: mapping.targetRelativePath)
        let destination = MigrationTreeScanner.joinRoot(plan.targetContainerPath, targetRelative)
        let destDir = (destination as NSString).deletingLastPathComponent
        let destName = (destination as NSString).lastPathComponent

        try fm.createDirectory(atPath: destDir, withIntermediateDirectories: true, attributes: nil)

        // Journal the temp BEFORE writing so a kill mid-write leaves a
        // precisely findable orphan. Name generation, journal, and the
        // actual open() all share this one variable.
        let tempName = destName + ".\(UUID().uuidString)" + MigrationFileCopy.partialSuffix
        let tempPath = (destDir as NSString).appendingPathComponent(tempName)
        try? MigrationCheckpointStore.notePendingTemp(planID: plan.id, tempName: tempName)
        defer { MigrationCheckpointStore.clearPendingTemp(planID: plan.id, tempName: tempName) }

        // CAS baseline: what the destination must look like when we commit.
        let expected: MigrationFileRecord?
        if fm.fileExists(atPath: destination) {
            guard let st = lstat(destination) else {
                throw EngineError.destinationChanged(destination)
            }
            expected = MigrationFileRecord(
                relativePath: targetRelative, isDirectory: false,
                byteCount: Int64(st.st_size), inode: UInt64(st.st_ino),
                device: UInt64(st.st_dev),
                modifiedAt: Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec)),
                sha256: nil
            )
        } else {
            expected = nil
        }

        _ = try MigrationFileCopy.copyToTemp(
            source: sourcePath, tempPath: tempPath, token: token
        )
        try MigrationFileCopy.commitTemp(
            tempPath: tempPath, destination: destination,
            expected: expected, token: token
        )
    }

    private func handleDirectory(_ record: MigrationFileRecord, plan: MigrationPlan, fm: FileManager) throws {
        let mapping = mapping(for: record.relativePath, plan: plan)
        let targetRelative = remapRelative(record.relativePath, from: mapping.sourceRelativePath,
                                           to: mapping.targetRelativePath)
        let destination = MigrationTreeScanner.joinRoot(plan.targetContainerPath, targetRelative)

        var isDir: ObjCBool = false
        if fm.fileExists(atPath: destination, isDirectory: &isDir) {
            if isDir.boolValue { return }
            // Target exists as a FILE where the source has a directory —
            // replace removes it; merge refuses (ambiguous ownership).
            guard plan.mode == .replace else {
                throw EngineError.destinationChanged("file blocks directory: \(destination)")
            }
            try fm.removeItem(atPath: destination)
        }
        try fm.createDirectory(atPath: destination, withIntermediateDirectories: true, attributes: nil)
    }

    /// replace-only: deletes target entries under mapped roots that the
    /// source tree does not have. Directories are swept deepest-first.
    private func sweepTargetOnly(plan: MigrationPlan, fm: FileManager) throws {
        guard let token = token else { throw EngineError.cancelled }
        let sourcePaths = Set(plan.files.map(\.relativePath))

        for mapping in plan.mappings {
            let targetRoot = MigrationTreeScanner.joinRoot(plan.targetContainerPath, mapping.targetRelativePath)
            guard fm.fileExists(atPath: targetRoot) else { continue }
            var all: [(path: String, isDir: Bool)] = []
            collectTree(targetRoot, into: &all, fm: fm)
            // Deepest-first so directories empty out before removal.
            all.sort { $0.path.count > $1.path.count }
            for entry in all {
                try token.check()
                let projected = projectedSourcePath(entryPath: entry.path,
                                                    targetRoot: targetRoot,
                                                    mapping: mapping)
                if !sourcePaths.contains(projected) {
                    try fm.removeItem(atPath: entry.path)
                }
            }
        }
    }

    /// Projects an absolute target path onto the source tree's relative
    /// namespace using the mapping (target root -> source root).
    private func projectedSourcePath(entryPath: String, targetRoot: String, mapping: MigrationMapping) -> String {
        MigrationPathMath.projectedSourcePath(entryPath: entryPath, targetRoot: targetRoot, mapping: mapping)
    }

    private func collectTree(_ root: String, into result: inout [(path: String, isDir: Bool)], fm: FileManager) {
        guard let names = try? fm.contentsOfDirectory(atPath: root) else { return }
        for name in names.sorted() {
            let full = (root as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: full, isDirectory: &isDir) else { continue }
            result.append((full, isDir.boolValue))
            if isDir.boolValue {
                collectTree(full, into: &result, fm: fm)
            }
        }
    }

    private func mapping(for relativePath: String, plan: MigrationPlan) -> MigrationMapping {
        MigrationPathMath.mapping(for: relativePath, in: plan.mappings) ?? plan.mappings[0]
    }

    /// Maps a source-relative path onto the target mapping root.
    private func remapRelative(_ relative: String, from sourceRoot: String, to targetRoot: String) -> String {
        MigrationPathMath.remap(relative, from: sourceRoot, to: targetRoot)
    }

    /// Removes journaled orphan partial temps left by a killed run.
    private func cleanOrphanTemps(plan: MigrationPlan) {
        let journal = MigrationCheckpointStore.readJournal(plan.id)
        guard !journal.pendingTemps.isEmpty else { return }
        let journalNames = Set(journal.pendingTemps)
        for mapping in plan.mappings {
            let targetRoot = MigrationTreeScanner.joinRoot(plan.targetContainerPath, mapping.targetRelativePath)
            var entries: [(path: String, isDir: Bool)] = []
            collectTree(targetRoot, into: &entries, fm: .default)
            for (path, isDir) in entries where !isDir {
                let name = (path as NSString).lastPathComponent
                // Remove exactly the journaled temps, plus any partial-suffix
                // straggler (a kill between notePendingTemp and journal flush
                // can leave an unjournaled one).
                if journalNames.contains(name) || name.contains(MigrationFileCopy.partialSuffix) {
                    try? FileManager.default.removeItem(atPath: path)
                }
            }
        }
        // Journal consumed.
        MigrationCheckpointStore.clearJournal(planID: plan.id)
    }

    // MARK: - Space

    private func enoughSpace(at path: String, needed: Int64) -> Bool {
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let available = values.volumeAvailableCapacityForImportantUsage else {
            return true // cannot measure: proceed, writes will fail loudly
        }
        return Int64(available) >= needed
    }

    private func lstat(_ path: String) -> stat? {
        var st = stat()
        guard Darwin.lstat(path, &st) == 0 else { return nil }
        return st
    }
}
