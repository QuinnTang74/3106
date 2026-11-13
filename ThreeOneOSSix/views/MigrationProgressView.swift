import SwiftUI
import UIKit

/// Live migration progress: ETA (per-item estimate, ScanCoordinator parity),
/// screen keep-awake while visible, background-task extension whose
/// expiration cancels into a clean interrupt, and the "don't leave this
/// page" warning.
struct MigrationProgressView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var taskCenter: MigrationTaskCenter

    @State private var startedAt = Date()
    @State private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    var body: some View {
        List {
            if let receipt = taskCenter.activeReceipt {
                Section {
                    LabeledContent(language.text("migration.progress.state"),
                                   value: stateText(receipt.state))
                    LabeledContent(language.text("migration.progress.files"),
                                   value: "\(receipt.completedFiles) / \(receipt.plan.fileCount)")
                    LabeledContent(language.text("migration.progress.bytes"),
                                   value: ByteCountFormatter.string(fromByteCount: receipt.completedBytes, countStyle: .file))
                    if let eta = etaSeconds(receipt) {
                        LabeledContent(language.text("migration.progress.eta"),
                                       value: etaText(eta))
                    }
                    if receipt.pendingExchange {
                        Text(language.text("migration.progress.pending_exchange"))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if let failure = receipt.failureReason {
                        Text(failure)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("\(receipt.plan.sourceBundleID) → \(receipt.plan.targetBundleID)")
                }
            } else {
                Section {
                    HStack { ProgressView().controlSize(.small) }
                }
            }

            Section {
                if taskCenter.isRunning {
                    Button(role: .destructive) {
                        taskCenter.cancelActive()
                    } label: {
                        Label(language.text("migration.progress.cancel"), systemImage: "stop.circle")
                    }
                } else {
                    Text(language.text("migration.progress.done_hint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                if taskCenter.isRunning {
                    Text(language.text("migration.progress.keep_open"))
                }
            }
        }
        .navigationTitle(language.text("migration.progress.title"))
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(taskCenter.isRunning)
        .onAppear {
            startedAt = Date()
            UIApplication.shared.isIdleTimerDisabled = true
            beginBackgroundTask()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            endBackgroundTask()
        }
    }

    private func stateText(_ state: MigrationReceipt.State) -> String {
        switch state {
        case .prepared: return language.text("migration.progress.state.prepared")
        case .running: return language.text("migration.progress.state.running")
        case .interrupted: return language.text("migration.progress.state.interrupted")
        case .completed: return language.text("migration.progress.state.completed")
        case .failed: return language.text("migration.progress.state.failed")
        }
    }

    /// Per-item ETA (fraction × average pace), ScanCoordinator parity.
    private func etaSeconds(_ receipt: MigrationReceipt) -> Int64? {
        guard receipt.plan.fileCount > receipt.completedFiles, receipt.completedFiles > 0 else { return nil }
        let elapsed = Date().timeIntervalSince(startedAt)
        guard elapsed > 0 else { return nil }
        let perItem = elapsed / Double(receipt.completedFiles)
        return Int64(max(1, perItem * Double(receipt.plan.fileCount - receipt.completedFiles)))
    }

    private func etaText(_ seconds: Int64) -> String {
        if seconds >= 3600 {
            return language.text("migration.progress.eta_hours", seconds / 3600, (seconds % 3600) / 60)
        }
        return language.text("migration.progress.eta_minutes", max(1, seconds / 60))
    }

    private func beginBackgroundTask() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "migration-run") {
            // Expiration: cancel into a clean interrupt; the checkpoint trail
            // lets the user resume from the backup tab.
            taskCenter.cancelActive()
            endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}
