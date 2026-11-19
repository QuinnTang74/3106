import SwiftUI

/// Explicit entry point for the kernel chain.
///
/// Before this screen existed the chain ran automatically at launch, which had
/// two problems that are not obvious from the code:
/// - the chain can reboot the device when a race is lost, and nothing told the
///   user an exploit was being run;
/// - the status it produced was never rendered anywhere in the UI, so a silent
///   failure looked identical to "nothing to do".
///
/// Everything the user needs is on this screen: what is about to run, its live
/// log, and the backend and duration of the last attempt.
struct UnlockView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var logStore = AppLog.shared

    var body: some View {
        List {
            backendSection
            statusSection
            actionSection
            logSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(language.text("unlock.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var backendSection: some View {
        Section {
            LabeledContent(language.text("unlock.backend")) {
                Text(SandboxAccess.backend.displayName)
                    .font(.footnote.monospaced())
            }
            LabeledContent(language.text("unlock.os")) {
                Text("iOS \(AppInfo.osVersion) (\(AppInfo.osBuild))")
                    .font(.footnote.monospaced())
            }
        } header: {
            Label(language.text("unlock.title"), systemImage: "lock.open")
        } footer: {
            Text(language.text("unlock.footer"))
        }
    }

    private var statusSection: some View {
        Section(language.text("unlock.status")) {
            switch appState.exploitStatus {
            case .notStarted:
                Text(language.text("status.not_attempted"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .success(let method):
                LabeledContent(language.text("unlock.result")) {
                    Label(method, systemImage: "checkmark.seal.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
                if let duration = KernelExploit.lastDuration {
                    LabeledContent(language.text("unlock.duration")) {
                        Text(String(format: "%.1fs", duration))
                            .font(.footnote.monospaced())
                    }
                }
            case .failed(let method, let code):
                LabeledContent(language.text("unlock.result")) {
                    Label("\(method) (\(code))", systemImage: "xmark.octagon.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                if let duration = KernelExploit.lastDuration {
                    LabeledContent(language.text("unlock.duration")) {
                        Text(String(format: "%.1fs", duration))
                            .font(.footnote.monospaced())
                    }
                }
            case .unsupported(let message):
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var actionSection: some View {
        Section {
            Button {
                appState.runKernelExploitIfNeeded()
            } label: {
                HStack {
                    if appState.kernelExploitRunning {
                        ProgressView()
                            .padding(.trailing, 4)
                    }
                    Text(appState.kernelExploitRunning
                         ? language.text("unlock.running")
                         : language.text("unlock.run"))
                }
            }
            .disabled(appState.kernelExploitRunning)
        } footer: {
            // Concrete, because a reboot mid-chain is a real outcome and the
            // user should know it before pressing rather than after.
            Text(language.text("unlock.warning"))
        }
    }

    private var logSection: some View {
        Section(language.text("unlock.log")) {
            if logStore.entries.isEmpty {
                Text(language.text("unlock.log_empty"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                // Last entries first: the interesting line is almost always the
                // most recent one.
                ForEach(Array(logStore.entries.suffix(60).reversed().enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }
}