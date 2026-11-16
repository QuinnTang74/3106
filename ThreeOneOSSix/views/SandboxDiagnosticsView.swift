import SwiftUI

/// Settings-page diagnostics surface for the sandbox grant chain (spec
/// 02-00-ios27-grant-hardening, F-01/D-06): real-time probe, the recent
/// grant ring, and a paste-ready export for remote attribution. Modeled
/// after LogView's share/copy pattern.
struct SandboxDiagnosticsView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @State private var probeRunning = false
    @State private var probeResult: Bool?
    @State private var copied = false
    @State private var clearTick = 0

    var body: some View {
        List {
            Section(language.text("sandbox.diag.section_backend")) {
                LabeledContent(language.text("settings.access_backend"), value: SandboxAccess.backend.displayName)
                LabeledContent(language.text("settings.app_group"), value: SandboxAccess.appGroup ?? "(none)")
                LabeledContent(
                    language.text("sandbox.diag.probe_state"),
                    value: probeResult.map { $0 ? "OK" : "FAILED" } ?? language.text("sandbox.diag.probe_not_run")
                )
                Button {
                    runProbe()
                } label: {
                    if probeRunning {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(language.text("sandbox.diag.probe_running"))
                        }
                    } else {
                        Label(language.text("sandbox.diag.probe_run"), systemImage: "stethoscope")
                    }
                }
                .disabled(probeRunning)
            }

            Section {
                ForEach(SandboxDiagnostics.recentGrants.reversed()) { record in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(Self.timeText(record.at))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(record.code >= 0 ? "OK" : "FAIL \(record.code)")
                                .font(.caption.monospaced().weight(.semibold))
                                .foregroundStyle(record.code >= 0 ? .green : .red)
                        }
                        Text(record.path)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                }
            } header: {
                Text(language.text("sandbox.diag.section_grants"))
            } footer: {
                Text(language.text("sandbox.diag.grants_footer"))
            }

            Section {
                Button {
                    copyReport()
                } label: {
                    Label(
                        copied ? language.text("sandbox.diag.copied") : language.text("sandbox.diag.copy"),
                        systemImage: copied ? "checkmark.circle" : "doc.on.doc"
                    )
                }
            } footer: {
                Text(language.text("sandbox.diag.export_footer"))
            }
        }
        .navigationTitle(language.text("sandbox.diag.title"))
        .navigationBarTitleDisplayMode(.inline)
        .id(clearTick)
    }

    private func runProbe() {
        probeRunning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = SandboxAccess.probe()
            DispatchQueue.main.async {
                probeResult = result
                probeRunning = false
            }
        }
    }

    private func copyReport() {
        UIPasteboard.general.string = SandboxDiagnostics.exportText(
            probeResult: probeResult,
            lsLayoutHit: Self.lsLayoutSummary()
        )
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copied = false
        }
    }

    /// LS-store layout hit + mapped container count + worse_query index
    /// size (spec F-07): a 27.3 device reporting this line lets an off-site
    /// calibration distinguish a layout miss from a query-side failure.
    static func lsLayoutSummary() -> String? {
        guard let snapshot = ContainerStore.launchServicesSnapshot() else { return nil }
        let indexCount = worse_query_identifier_paths().count
        return "layout=\(snapshot.layoutLabel) "
            + "mapped=\(snapshot.mappedContainerCount) "
            + "wq-index=\(indexCount)"
    }

    private static func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
