import SwiftUI
import UniformTypeIdentifiers

/// Stored configuration packages (.3106cfg): export the picked app's
/// Preferences as a shareable package, import packages picked from Files,
/// and apply any stored set onto an arbitrary app (replace/merge).
struct MigrationConfigBackupView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var taskCenter: MigrationTaskCenter

    @State private var showExporter = false
    @State private var exportApp: InstalledApp?
    @State private var plistOnly = true
    @State private var showImporter = false
    @State private var applySet: MigrationConfigBackupService.ImportedSet?
    @State private var applyMode: TransferMode = .merge
    @State private var applyTarget: InstalledApp?
    @State private var errorMessage: String?
    @State private var exportURL: URL?
    @State private var showShare = false

    var body: some View {
        List {
            exportSection
            storedSection
        }
        .navigationTitle(language.text("configbackup.title"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showExporter) {
            // Export needs exactly one app; reuse the two-step picker but
            // complete on the first pick via an onChange trap.
            MigrationAppPicker { source, _ in
                showExporter = false
                exportPackage(from: source)
            }
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [UTType(filenameExtension: MigrationConfigBackupService.packageExtension) ?? .data],
                      allowsMultipleSelection: false) { result in
            importPackage(result)
        }
        .sheet(isPresented: $showShare) {
            if let url = exportURL {
                ActivityShareSheet(items: [url])
                    .onDisappear {
                        // The scratch zip stays for retries; the session
                        // TempSpaceRegistry lease expires it later. Drop the
                        // reference so a re-export can overwrite cleanly.
                        exportURL = nil
                    }
            }
        }
        .sheet(item: $applySet) { set in
            NavigationStack {
                MigrationApplyConfigView(set: set) { set, target, mode in
                    apply(set: set, to: target, mode: mode)
                }
            }
        }
        .alert(language.text("configbackup.error.title"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil }
        })) {
            Button(language.text("common.ok"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear { taskCenter.refreshStoredSets() }
    }

    // MARK: - Export

    @ViewBuilder
    private var exportSection: some View {
        Section {
            Button {
                showExporter = true
            } label: {
                Label(language.text("configbackup.export"), systemImage: "square.and.arrow.up")
            }
            Toggle(language.text("configbackup.plist_only"), isOn: $plistOnly)
        } header: {
            Text(language.text("configbackup.section.export"))
        } footer: {
            Text(language.text("configbackup.export.footer"))
        }
    }

    @ViewBuilder
    private var storedSection: some View {
        Section {
            if taskCenter.storedSets.isEmpty {
                Text(language.text("configbackup.stored.empty"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(taskCenter.storedSets) { set in
                NavigationLink {
                    MigrationConfigSetDetail(set: set)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(set.manifest.sourceAppName)
                            .font(.subheadline.weight(.medium))
                        Text("\(set.manifest.sourceBundleID) · \(set.manifest.files.count) files · \(set.manifest.plistOnly ? "plist" : "full")")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Button {
                showImporter = true
            } label: {
                Label(language.text("configbackup.import"), systemImage: "square.and.arrow.down")
            }
        } header: {
            Text(language.text("configbackup.section.stored"))
        }
    }

    // MARK: - Actions

    private func exportPackage(from app: InstalledApp) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let url = try MigrationConfigBackupService.exportPackage(app: app, plistOnly: plistOnly)
                DispatchQueue.main.async {
                    exportURL = url
                    showShare = true
                }
            } catch {
                DispatchQueue.main.async {
                    errorMessage = String(describing: error)
                }
            }
        }
    }

    private func importPackage(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            _ = try MigrationConfigBackupService.importPackage(at: url)
            taskCenter.refreshStoredSets()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func apply(set: MigrationConfigBackupService.ImportedSet,
                       to target: InstalledApp, mode: TransferMode) {
        applySet = nil
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try MigrationConfigBackupService.apply(set, to: target, mode: mode)
                DispatchQueue.main.async {
                    log("configbackup: applied to \(target.bundleID)")
                }
            } catch {
                DispatchQueue.main.async {
                    errorMessage = String(describing: error)
                }
            }
        }
    }
}

// MARK: - Apply flow

/// Second sheet stage for applying a stored set: pick target app + mode.
struct MigrationApplyConfigView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss

    let set: MigrationConfigBackupService.ImportedSet
    let onApply: (MigrationConfigBackupService.ImportedSet, InstalledApp, TransferMode) -> Void

    @State private var target: InstalledApp?
    @State private var mode: TransferMode = .merge

    var body: some View {
        List {
            if let target = target {
                Section {
                    LabeledContent(language.text("migration.preview.target"), value: target.displayName)
                    Picker(language.text("migration.mode"), selection: $mode) {
                        Text(language.text("migration.mode.merge")).tag(TransferMode.merge)
                        Text(language.text("migration.mode.replace")).tag(TransferMode.replace)
                    }
                    Button(language.text("configbackup.apply.confirm")) {
                        onApply(set, target, mode)
                    }
                    .fontWeight(.semibold)
                } footer: {
                    Text(language.text("configbackup.apply.footer"))
                }
            }
            Section {
                AppListForPick { app in
                    target = app
                }
            } header: {
                Text(language.text("configbackup.apply.pick_header"))
            }
        }
        .navigationTitle(language.text("configbackup.apply.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Minimal app list used by the config-apply flow (reuses eligibleApps).
struct AppListForPick: View {
    @State private var apps: [InstalledApp] = []
    @State private var hasLoaded = false
    let onPick: (InstalledApp) -> Void

    var body: some View {
        if apps.isEmpty {
            HStack { ProgressView().controlSize(.small) }
        }
        ForEach(apps) { app in
            Button {
                onPick(app)
            } label: {
                HStack(spacing: 10) {
                    AppCardRowIcon(image: app.icon)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.displayName).font(.subheadline.weight(.medium))
                        Text(app.bundleID)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
        }
        .onAppear {
            guard !hasLoaded else { return }
            hasLoaded = true
            DispatchQueue.global(qos: .userInitiated).async {
                let loaded = AppSaveBackupService.eligibleApps()
                DispatchQueue.main.async { apps = loaded }
            }
        }
    }
}

/// Detail view for one stored set: manifest listing + delete.
struct MigrationConfigSetDetail: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var taskCenter: MigrationTaskCenter
    @Environment(\.dismiss) private var dismiss

    let set: MigrationConfigBackupService.ImportedSet

    var body: some View {
        List {
            Section {
                LabeledContent(language.text("migration.preview.source"), value: set.manifest.sourceAppName)
                LabeledContent(language.text("configbackup.detail.files"),
                               value: "\(set.manifest.files.count)")
                LabeledContent(language.text("configbackup.detail.scope"),
                               value: set.manifest.plistOnly ? "plist" : "full")
            }
            Section {
                ForEach(set.manifest.files.prefix(50), id: \.path) { record in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.path).font(.caption.monospaced())
                        Text(ByteCountFormatter.string(fromByteCount: record.bytes, countStyle: .file))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if set.manifest.files.count > 50 {
                    Text(language.text("configbackup.detail.more", Int64(set.manifest.files.count - 50)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(language.text("configbackup.detail.list_header"))
            }
            Section {
                Button(role: .destructive) {
                    MigrationConfigBackupService.deleteSet(set)
                    taskCenter.refreshStoredSets()
                    dismiss()
                } label: {
                    Label(language.text("configbackup.detail.delete"), systemImage: "trash")
                }
            }
        }
        .navigationTitle(set.manifest.sourceAppName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - UIActivityViewController bridge (completion-driven cleanup)

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onDismiss: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            onDismiss()
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
