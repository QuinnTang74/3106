import SwiftUI

/// The backup tab: automatic per-write snapshots, manual backups, full
/// device-workspace archive and one-tap restore. Skeleton for S2 navigation;
/// full backup flows land in S6 on top of BackupCenter.
struct BackupTabView: View {
    @Environment(\.appLanguage) private var language
    private let backupCenter = BackupCenter.shared
    let onOpenSettings: () -> Void
    let onOpenLogs: () -> Void

    init(
        onOpenSettings: @escaping () -> Void = {},
        onOpenLogs: @escaping () -> Void = {}
    ) {
        self.onOpenSettings = onOpenSettings
        self.onOpenLogs = onOpenLogs
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(language.text("backup.tab.auto_note"), systemImage: "checkmark.seal")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Label(language.text("backup.tab.auto_header"), systemImage: "arrow.triangle.2.circlepath")
                } footer: {
                    Text(language.text("backup.tab.auto_footer"))
                }

                Section {
                    LabeledContent(language.text("backup.tab.snapshot_count")) {
                        Text("\(backupCenter.records().count)")
                            .monospacedDigit()
                    }
                    LabeledContent(language.text("backup.tab.storage_usage")) {
                        Text(ByteCountFormatter.string(
                            fromByteCount: backupCenter.storageUsage(),
                            countStyle: .file
                        ))
                        .monospacedDigit()
                    }
                } header: {
                    Label(language.text("backup.tab.snapshots_header"), systemImage: "archivebox")
                }
            }
            .navigationTitle(language.text("backup.tab.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { onOpenSettings() } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(language.text("settings.title"))
                }
            }
        }
    }
}
