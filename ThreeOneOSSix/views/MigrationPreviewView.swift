import SwiftUI

/// Pre-run summary: total bytes/files across mappings, the mapping list,
/// and the two WCMigrate-style confirmations (apps quit + intent confirmed)
/// before handing off to the risk screen.
struct MigrationPreviewView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss

    let flow: MigrationFlow
    let selected: [MigrationMapping]
    let mode: TransferMode
    let preSnapshotTarget: Bool
    let onConfirm: (TransferMode) -> Void

    @State private var totalBytes: Int64?
    @State private var fileCount: Int?
    @State private var appsQuit = false
    @State private var intentConfirmed = false

    var body: some View {
        List {
            Section {
                LabeledContent(language.text("migration.preview.source"),
                               value: "\(flow.source.displayName)")
                LabeledContent(language.text("migration.preview.target"),
                               value: "\(flow.target.displayName)")
                LabeledContent(language.text("migration.preview.mode"),
                               value: language.text("migration.mode.\(mode.rawValue)"))
                if let bytes = totalBytes, let files = fileCount {
                    LabeledContent(language.text("migration.preview.files"),
                                   value: language.text("migration.preview.files_value", Int64(files)))
                    LabeledContent(language.text("migration.preview.bytes"),
                                   value: ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                } else {
                    LabeledContent(language.text("migration.preview.measuring")) {
                        ProgressView().controlSize(.small)
                    }
                }
                if preSnapshotTarget {
                    Text(language.text("migration.preview.presnapshot_note"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(language.text("migration.preview.summary"))
            }

            Section {
                ForEach(selected) { mapping in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mapping.sourceRelativePath)
                            .font(.caption.monospaced())
                        Text("→ \(mapping.targetRelativePath)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(language.text("migration.section.selected", Int64(selected.count)))
            }

            Section {
                Toggle(language.text("migration.preview.apps_quit"), isOn: $appsQuit)
                Toggle(language.text("migration.preview.intent"), isOn: $intentConfirmed)
            } footer: {
                Text(language.text("migration.preview.footer"))
            }

            Section {
                Button {
                    onConfirm(mode)
                } label: {
                    Text(language.text("migration.preview.continue"))
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .disabled(!appsQuit || !intentConfirmed)
            }
        }
        .navigationTitle(language.text("migration.preview"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { measure() }
    }

    /// Quick source-side measurement (per-level grant, no engine prepare).
    private func measure() {
        DispatchQueue.global(qos: .userInitiated).async {
            let grant = ContainerStore.grantContainerAccess(flow.source.containerPath)
            defer {
                if grant >= 0 { SandboxAccess.release(grant) }
            }
            var bytes: Int64 = 0
            var files = 0
            let fm = FileManager.default
            for mapping in selected {
                let root = MigrationTreeScanner.joinRoot(flow.source.containerPath, mapping.sourceRelativePath)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: root, isDirectory: &isDir) else { continue }
                if !isDir.boolValue {
                    if let dict = try? fm.attributesOfItem(atPath: root),
                       let size = (dict[.size] as? NSNumber)?.int64Value {
                        bytes += size
                    }
                    files += 1
                    continue
                }
                var queue = [root]
                while let dir = queue.first {
                    queue.removeFirst()
                    guard let names = try? fm.contentsOfDirectory(atPath: dir) else { continue }
                    for name in names {
                        let full = (dir as NSString).appendingPathComponent(name)
                        var childDir: ObjCBool = false
                        guard fm.fileExists(atPath: full, isDirectory: &childDir) else { continue }
                        if childDir.boolValue {
                            queue.append(full)
                        } else {
                            files += 1
                            if let dict = try? fm.attributesOfItem(atPath: full),
                               let size = (dict[.size] as? NSNumber)?.int64Value {
                                bytes += size
                            }
                        }
                    }
                }
            }
            DispatchQueue.main.async {
                totalBytes = bytes
                fileCount = files
            }
        }
    }
}
