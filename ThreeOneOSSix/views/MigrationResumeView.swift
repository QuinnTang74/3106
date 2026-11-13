import SwiftUI

/// "Check and continue" for an interrupted migration: shows the validation
/// verdict, lets the user pick verification depth, and resumes when ready.
/// An exchange interrupted mid-swap requires the manual "already swapped?"
/// acknowledgement before the resume button enables.
struct MigrationResumeView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var taskCenter: MigrationTaskCenter

    let receipt: MigrationReceipt

    @State private var depth: MigrationResumeService.ValidationDepth = .fast
    @State private var report: MigrationResumeService.ValidationReport?
    @State private var exchangeAcknowledged = false
    @State private var isResuming = false

    var body: some View {
        List {
            Section {
                LabeledContent(language.text("migration.resume.source"),
                               value: receipt.plan.sourceBundleID)
                LabeledContent(language.text("migration.resume.target"),
                               value: receipt.plan.targetBundleID)
                LabeledContent(language.text("migration.preview.mode"),
                               value: language.text("migration.mode.\(receipt.plan.mode.rawValue)"))
                LabeledContent(language.text("migration.progress.files"),
                               value: "\(receipt.completedFiles) / \(receipt.plan.fileCount)")
                if let reason = receipt.failureReason {
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text(language.text("migration.resume.task_header"))
            }

            if receipt.pendingExchange {
                Section {
                    Text(language.text("migration.resume.exchange_warning"))
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                    Toggle(language.text("migration.resume.exchange_ack"), isOn: $exchangeAcknowledged)
                } footer: {
                    Text(language.text("migration.resume.exchange_footer"))
                }
            }

            Section {
                Picker(language.text("migration.resume.depth"), selection: $depth) {
                    Text(language.text("migration.resume.depth.fast")).tag(MigrationResumeService.ValidationDepth.fast)
                    Text(language.text("migration.resume.depth.deep")).tag(MigrationResumeService.ValidationDepth.deep)
                }
                Button(language.text("migration.resume.validate")) {
                    validate()
                }
                if let report = report {
                    verdictRow(report)
                    if !report.mismatches.isEmpty {
                        ForEach(report.mismatches.prefix(10), id: \.self) { path in
                            Text(path).font(.caption2.monospaced()).foregroundStyle(.red)
                        }
                        if report.mismatches.count > 10 {
                            Text(language.text("migration.resume.more_mismatches", Int64(report.mismatches.count - 10)))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text(language.text("migration.resume.check_header"))
            } footer: {
                Text(language.text("migration.resume.depth_footer"))
            }

            Section {
                Button {
                    isResuming = true
                    resume()
                } label: {
                    Label(language.text("migration.resume.continue"), systemImage: "play.circle")
                        .fontWeight(.semibold)
                }
                .disabled(!canResume)

                Button(role: .destructive) {
                    taskCenter.dismissReceipt(receipt)
                    dismiss()
                } label: {
                    Label(language.text("migration.resume.discard"), systemImage: "trash")
                }
            }
        }
        .navigationTitle(language.text("migration.resume.title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: validate)
    }

    private var canResume: Bool {
        guard !isResuming, let report = report else { return false }
        if case .ready = report.verdict {
            if receipt.pendingExchange { return exchangeAcknowledged }
            return true
        }
        return false
    }

    @ViewBuilder
    private func verdictRow(_ report: MigrationResumeService.ValidationReport) -> some View {
        HStack(spacing: 8) {
            switch report.verdict {
            case .ready:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(language.text("migration.resume.verdict.ready"))
                    .font(.subheadline)
            case .alreadyCompleted:
                Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
                Text(language.text("migration.resume.verdict.completed"))
                    .font(.subheadline)
            case .exchangeNeedsManualCheck:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(language.text("migration.resume.verdict.exchange"))
                    .font(.subheadline)
            case .containerMoved:
                Image(systemName: "arrow.triangle.swap").foregroundStyle(.orange)
                Text(language.text("migration.resume.verdict.moved"))
                    .font(.subheadline)
            case .appMissing(let side):
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                Text(language.text("migration.resume.verdict.missing", side))
                    .font(.subheadline)
            case .targetChanged(let path):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                Text(language.text("migration.resume.verdict.changed", path))
                    .font(.subheadline)
            }
            Spacer()
            if report.verifiedFiles > 0 {
                Text(language.text("migration.resume.verified", Int64(report.verifiedFiles)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func validate() {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = MigrationCheckpointStore.loadPlan(planID: receipt.id).map { plan -> MigrationResumeService.ValidationReport in
                let resolvedSource = ContainerStore.resolveAppContainerPath(bundleID: plan.sourceBundleID)
                let resolvedTarget = ContainerStore.resolveAppContainerPath(bundleID: plan.targetBundleID)
                return MigrationResumeService.validate(receipt, resolvedSource: resolvedSource,
                                                       resolvedTarget: resolvedTarget,
                                                       depth: depth)
            } ?? MigrationResumeService.ValidationReport(verdict: .appMissing(side: receipt.plan.sourceBundleID),
                                                         mismatches: [], verifiedFiles: 0)
            DispatchQueue.main.async {
                report = result
            }
        }
    }

    private func resume() {
        Task {
            let verdict = await taskCenter.resume(receipt: receipt)
            await MainActor.run {
                isResuming = false
                if let verdict = verdict {
                    report = MigrationResumeService.ValidationReport(verdict: verdict,
                                                                     mismatches: [], verifiedFiles: 0)
                } else if taskCenter.isRunning {
                    dismiss()
                } else {
                    dismiss()
                }
            }
        }
    }
}
