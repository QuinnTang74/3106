import Foundation
import Combine

/// @MainActor state hub for migration tasks: pending resumes surfaced at
/// launch, in-flight progress for the picker flow, and the stored-config
/// sets. Injected as an EnvironmentObject (pattern matches PatchProjectStore).
@MainActor
final class MigrationTaskCenter: ObservableObject {

    @Published var pendingResumes: [MigrationReceipt] = []
    @Published var activeReceipt: MigrationReceipt?
    @Published var isRunning = false
    @Published var storedSets: [MigrationConfigBackupService.ImportedSet] = []

    private var engine: MigrationEngine?
    private var token: CancellationToken?
    /// Root grants held for the whole task (prepare + run). Released on
    /// every exit path — releasing early makes device reads EPERM.
    private var heldPair: MigrationAppResolver.ResolvedPair?
    private var progressSink: AnyCancellable?
    /// UI-thread receipt updates coalesce here; throttled downstream.
    private let progressSubject = PassthroughSubject<MigrationReceipt, Never>()

    init() {
        progressSink = progressSubject
            .throttle(for: .milliseconds(250), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] receipt in
                self?.activeReceipt = receipt
            }
    }

    // MARK: - Discovery

    /// Called from App startup (and on backup-tab appear): refreshes the
    /// "check and continue" list.
    func refreshPendingResumes() {
        pendingResumes = MigrationResumeService.scanInterrupted()
    }

    func refreshStoredSets() {
        storedSets = MigrationConfigBackupService.storedSets()
    }

    func dismissReceipt(_ receipt: MigrationReceipt) {
        pendingResumes.removeAll { $0.id == receipt.id }
        MigrationCheckpointStore.remove(planID: receipt.id)
    }

    // MARK: - Run lifecycle

    /// Full fresh-run lifecycle: resolve + hold grants, prepare, run, release.
    /// The UI awaits this; progress arrives through activeReceipt.
    func startTask(source: InstalledApp, target: InstalledApp,
                   mappings: [MigrationMapping], mode: TransferMode,
                   preSnapshotTarget: Bool) async {
        guard !isRunning else { return }
        isRunning = true
        activeReceipt = nil

        let token = CancellationToken()
        let engine = MigrationEngine()
        self.token = token
        self.engine = engine

        do {
            let resolved = try MigrationAppResolver.resolve(
                sourceBundleID: source.bundleID, targetBundleID: target.bundleID
            )
            heldPair = resolved
            let plan = try await engine.prepare(
                source: source, target: target, mappings: mappings,
                mode: mode, preSnapshotTarget: preSnapshotTarget
            )
            let receipt = try await engine.run(plan: plan, token: token) { [progressSubject] receipt in
                progressSubject.send(receipt)
            }
            isRunning = false
            activeReceipt = receipt
            finishCurrentTask()
            refreshPendingResumes()
        } catch is CancellationError {
            isRunning = false
            finishCurrentTask()
            refreshPendingResumes()
        } catch {
            isRunning = false
            // Surface the engine's persisted failure state when it wrote one.
            let all = MigrationCheckpointStore.loadAll()
            if let latest = all.first(where: { $0.state == .failed || $0.state == .interrupted }) {
                activeReceipt = latest
            }
            finishCurrentTask()
            refreshPendingResumes()
            log("migration: failed — \(error)")
        }
    }

    func cancelActive() {
        token?.cancel(reason: "user requested from UI")
    }

    /// Releases grants and drops engine state. Safe to call repeatedly.
    private func finishCurrentTask() {
        heldPair?.release()
        heldPair = nil
        engine = nil
        token = nil
    }

    /// Resume entry point: revalidates, then continues the stored plan.
    /// Grants are held for validate + run together and released on every
    /// exit path — releasing between the two makes device reads EPERM.
    func resume(receipt: MigrationReceipt) async -> ResumeVerdict? {
        guard let plan = MigrationCheckpointStore.loadPlan(planID: receipt.id) else {
            dismissReceipt(receipt)
            return nil
        }
        let resolved: MigrationAppResolver.ResolvedPair
        do {
            resolved = try MigrationAppResolver.resolve(
                sourceBundleID: plan.sourceBundleID,
                targetBundleID: plan.targetBundleID
            )
        } catch {
            return .appMissing(side: plan.sourceBundleID)
        }
        defer { resolved.release() }

        let report = MigrationResumeService.validate(
            receipt, resolvedSource: resolved.sourcePath,
            resolvedTarget: resolved.targetPath, depth: .fast
        )
        guard case .ready = report.verdict else {
            return report.verdict
        }

        let engine = MigrationEngine()
        let token = CancellationToken()
        self.engine = engine
        self.token = token
        isRunning = true
        do {
            let updated = try await engine.run(plan: plan, resumeState: receipt, token: token) { [progressSubject] receipt in
                progressSubject.send(receipt)
            }
            isRunning = false
            activeReceipt = updated
            refreshPendingResumes()
            return nil
        } catch is CancellationError {
            isRunning = false
            refreshPendingResumes()
            return nil
        } catch {
            isRunning = false
            refreshPendingResumes()
            log("migration resume: failed — \(error)")
            return nil
        }
    }
}
