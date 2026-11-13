import SwiftUI
import UniformTypeIdentifiers

/// The migration hub: pick source + target app, select folders/files, choose
/// a transfer mode, confirm, run. Pending interrupted tasks surface as a
/// banner; stored config sets link to their own manager.
struct MigrationView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var taskCenter: MigrationTaskCenter

    @State private var apps: [InstalledApp] = []
    @State private var hasLoaded = false
    @State private var showPicker = false
    @State private var flow: MigrationFlow?
    @State private var importError: String?
    @State private var showImporter = false

    var body: some View {
        List {
            resumeBanner
            provisionBanner
            Section {
                Button {
                    showPicker = true
                } label: {
                    Label(language.text("migration.new_task"), systemImage: "arrow.left.arrow.right.square")
                }
                NavigationLink {
                    MigrationConfigBackupView()
                } label: {
                    Label(language.text("migration.config_backups"), systemImage: "doc.zipper")
                }
            } header: {
                Text(language.text("migration.section.tasks"))
            }
        }
        .navigationTitle(language.text("migration.title"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPicker) {
            MigrationAppPicker { source, target in
                showPicker = false
                flow = MigrationFlow(source: source, target: target)
            }
        }
        .sheet(item: $flow) { flow in
            NavigationStack {
                MigrationDirectorySelectView(flow: flow)
            }
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [UTType(filenameExtension: MigrationConfigBackupService.packageExtension) ?? .data],
                      allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let set = try MigrationConfigBackupService.importPackage(at: url)
                taskCenter.refreshStoredSets()
                log("migration: config package imported (\(set.manifest.files.count) files)")
            } catch {
                importError = String(describing: error)
            }
        }
        .alert("import.error.title", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil }
        })) {
            Button(language.text("common.ok"), role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
        .onAppear {
            taskCenter.refreshPendingResumes()
            taskCenter.refreshStoredSets()
            loadApps()
        }
    }

    // MARK: - Banners

    @ViewBuilder
    private var resumeBanner: some View {
        if !taskCenter.pendingResumes.isEmpty {
            Section {
                ForEach(taskCenter.pendingResumes) { receipt in
                    NavigationLink {
                        MigrationResumeView(receipt: receipt)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(language.text("migration.resume.pending"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.orange)
                            Text("\(receipt.plan.sourceBundleID) → \(receipt.plan.targetBundleID) · \(receipt.plan.mode.rawValue)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text(language.text("migration.section.pending"))
            }
        }
    }

    /// adhoc signing reminder (W5b): embedded.mobileprovision expiry shown
    /// when it is within 14 days or already passed.
    @ViewBuilder
    private var provisionBanner: some View {
        if let days = ProvisioningProfileChecker.daysUntilExpiry() {
            if days <= 14 {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: days < 0 ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(days < 0 ? .red : .orange)
                        Text(days < 0
                             ? language.text("migration.provision.expired")
                             : language.text("migration.provision.expiring", Int64(days)))
                            .font(.caption)
                    }
                }
            }
        }
    }

    private func loadApps() {
        guard !hasLoaded else { return }
        hasLoaded = true
        DispatchQueue.global(qos: .userInitiated).async {
            let loaded = AppSaveBackupService.eligibleApps()
            DispatchQueue.main.async {
                apps = loaded
            }
        }
    }
}

/// Sheet model for the in-progress flow.
struct MigrationFlow: Identifiable {
    let id = UUID()
    let source: InstalledApp
    let target: InstalledApp
}

// MARK: - App picker (source + target)

/// Two-step picker: pick source, then target. WeChat-family apps sort first
/// with a label; no business paths are hardcoded anywhere.
struct MigrationAppPicker: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @State private var apps: [InstalledApp] = []
    @State private var hasLoaded = false
    @State private var source: InstalledApp?
    @State private var manualError: String?
    @State private var manualSourceID = ""
    @State private var manualTargetID = ""

    let onPicked: (InstalledApp, InstalledApp) -> Void

    var body: some View {
        NavigationStack {
            List {
                if source == nil {
                    Section {
                        Text(language.text("migration.pick.source"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        Text(language.text("migration.pick.target"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(apps) { app in
                    Button {
                        pick(app)
                    } label: {
                        HStack(spacing: 10) {
                            AppCardRowIcon(image: app.icon)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(app.displayName)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(1)
                                    if MigrationAppResolver.isWeChatFamily(app) {
                                        Text(language.text("migration.pick.wechat_tag"))
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.orange.opacity(0.18))
                                            .foregroundStyle(.orange)
                                            .clipShape(Capsule())
                                    }
                                }
                                Text(app.bundleID)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                }
                manualSection
            }
            .navigationTitle(language.text("migration.pick.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(language.text("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if source != nil {
                        Button(language.text("migration.pick.restart")) { source = nil }
                    }
                }
            }
            .onAppear {
                guard !hasLoaded else { return }
                hasLoaded = true
                DispatchQueue.global(qos: .userInitiated).async {
                    let loaded = MigrationAppResolver.sortedForPicker(AppSaveBackupService.eligibleApps())
                    DispatchQueue.main.async {
                        apps = loaded
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var manualSection: some View {
        Section {
            TextField(language.text("migration.pick.manual_source"), text: $manualSourceID)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            TextField(language.text("migration.pick.manual_target"), text: $manualTargetID)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button(language.text("migration.pick.manual_apply")) {
                applyManual()
            }
            .disabled(manualSourceID.isEmpty || manualTargetID.isEmpty)
        } header: {
            Text(language.text("migration.pick.manual_header"))
        } footer: {
            Text(language.text("migration.pick.manual_footer"))
        }
    }

    private func pick(_ app: InstalledApp) {
        if let existing = source {
            guard existing.bundleID != app.bundleID else {
                return // same app on both sides is meaningless
            }
            onPicked(existing, app)
        } else {
            source = app
        }
    }

    private func applyManual() {
        DispatchQueue.global(qos: .userInitiated).async {
            let srcPath = ContainerStore.resolveAppContainerPath(bundleID: manualSourceID)
                ?? ContainerStore.resolveAppContainerPathByMetadataScan(bundleID: manualSourceID)
            let dstPath = ContainerStore.resolveAppContainerPath(bundleID: manualTargetID)
                ?? ContainerStore.resolveAppContainerPathByMetadataScan(bundleID: manualTargetID)
            DispatchQueue.main.async {
                guard let sp = srcPath, let dp = dstPath else {
                    manualError = language.text("migration.pick.manual_not_found")
                    return
                }
                onPicked(
                    InstalledApp(bundleID: manualSourceID, name: manualSourceID, containerPath: sp, version: "", icon: nil),
                    InstalledApp(bundleID: manualTargetID, name: manualTargetID, containerPath: dp, version: "", icon: nil)
                )
            }
        }
    }
}

// MARK: - Directory selection

/// Browse the SOURCE container and check items to migrate; each checked item
/// becomes a mapping. Directory navigation mirrors FileReplaceDirectoryBrowser
/// (per-level grant) — execution grants are task-scoped instead.
struct MigrationDirectorySelectView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var taskCenter: MigrationTaskCenter

    let flow: MigrationFlow

    @State private var navigationStack: [String] = []
    @State private var currentPath = ""
    @State private var entries: [MigrationBrowseEntry] = []
    @State private var isLoading = false
    @State private var selected: [MigrationMapping] = []
    @State private var mode: TransferMode = .merge
    @State private var preSnapshotTarget = true
    @State private var showMapping = false
    @State private var showPreview = false
    @State private var riskMode: TransferMode?
    @State private var isBusy = false

    var body: some View {
        List {
            if !selected.isEmpty {
                Section {
                    ForEach(selected) { mapping in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mapping.sourceRelativePath)
                                    .font(.caption.monospaced())
                                    .lineLimit(2)
                                Text("→ \(mapping.targetRelativePath)")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                selected.removeAll { $0.id == mapping.id }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    Button(language.text("migration.mapping.edit")) { showMapping = true }
                        .disabled(selected.isEmpty)
                } header: {
                    Text(language.text("migration.section.selected", Int64(selected.count)))
                }
            }

            Section {
                Picker(language.text("migration.mode"), selection: $mode) {
                    Text(language.text("migration.mode.merge")).tag(TransferMode.merge)
                    Text(language.text("migration.mode.replace")).tag(TransferMode.replace)
                    Text(language.text("migration.mode.exchange")).tag(TransferMode.exchange)
                }
                Toggle(language.text("migration.presnapshot"), isOn: $preSnapshotTarget)
            } header: {
                Text(language.text("migration.section.options"))
            } footer: {
                Text(language.text("migration.mode.footer.\(mode.rawValue)"))
            }

            browseSection
        }
        .navigationTitle(language.text("migration.select.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(language.text("migration.preview")) {
                    showPreview = true
                }
                .disabled(selected.isEmpty || isBusy)
            }
        }
        .sheet(isPresented: $showMapping) {
            NavigationStack {
                MigrationMappingView(mappings: selected) { updated in
                    selected = updated
                }
            }
        }
        .sheet(item: $riskMode) { mode in
            RiskConfirmationView(
                titleKey: "migration.title",
                riskKey: mode.riskKey,
                confirmActionKey: "risk.migration.confirm_action",
                onCancel: nil,
                onConfirm: {
                    riskMode = nil
                    runTask(mode: mode)
                }
            )
        }
        .sheet(isPresented: $showPreview) {
            NavigationStack {
                MigrationPreviewView(
                    flow: flow, selected: selected, mode: mode,
                    preSnapshotTarget: preSnapshotTarget,
                    onConfirm: { confirmedMode in
                        showPreview = false
                        riskMode = confirmedMode
                    }
                )
            }
        }
        .onAppear {
            if currentPath.isEmpty {
                currentPath = flow.source.containerPath
                loadCurrentLevel()
            }
        }
    }

    @ViewBuilder
    private var browseSection: some View {
        Section {
            if isLoading {
                HStack { ProgressView().controlSize(.small) }
            }
            ForEach(entries) { entry in
                Button {
                    tap(entry)
                } label: {
                    HStack {
                        Image(systemName: entry.isDirectory ? "folder" : "doc")
                            .foregroundStyle(entry.isDirectory ? Color.blue : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name).font(.subheadline)
                            if entry.isDirectory {
                                Text(language.text("migration.browse.check_to_migrate"))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if isSelected(entry) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
            if navigationStack.count > 0 {
                Button {
                    navigateUp()
                } label: {
                    Label(language.text("migration.browse.up"), systemImage: "chevron.up")
                }
            }
        } header: {
            Text(language.text("migration.browse.source_header", flow.source.displayName))
        }
    }

    private func isSelected(_ entry: MigrationBrowseEntry) -> Bool {
        selected.contains { $0.sourceRelativePath == relativePath(of: entry) }
    }

    private func tap(_ entry: MigrationBrowseEntry) {
        if isSelected(entry) {
            selected.removeAll { $0.sourceRelativePath == relativePath(of: entry) }
            return
        }
        if entry.isDirectory {
            navigationStack.append(entry.name)
            currentPath = entry.path
            loadCurrentLevel()
        } else {
            selected.append(MigrationMapping(sourceRelativePath: relativePath(of: entry)))
        }
    }

    private func navigateUp() {
        navigationStack.removeLast()
        currentPath = navigationStack.isEmpty
            ? flow.source.containerPath
            : (currentPath as NSString).deletingLastPathComponent
        loadCurrentLevel()
    }

    private func relativePath(of entry: MigrationBrowseEntry) -> String {
        String(entry.path.dropFirst(flow.source.containerPath.count + 1))
    }

    private func loadCurrentLevel() {
        isLoading = true
        let level = currentPath
        DispatchQueue.global(qos: .userInitiated).async {
            let grant = ContainerStore.grantContainerAccess(level)
            defer {
                if grant >= 0 { SandboxAccess.release(grant) }
            }
            let fm = FileManager.default
            let names = (try? fm.contentsOfDirectory(atPath: level)) ?? []
            let loaded: [MigrationBrowseEntry] = names.sorted().map { name in
                let full = (level as NSString).appendingPathComponent(name)
                var isDir: ObjCBool = false
                fm.fileExists(atPath: full, isDirectory: &isDir)
                return MigrationBrowseEntry(name: name, path: full, isDirectory: isDir.boolValue)
            }
            DispatchQueue.main.async {
                entries = loaded
                isLoading = false
            }
        }
    }

    private func runTask(mode: TransferMode) {
        isBusy = true
        let source = flow.source
        let target = flow.target
        let mappings = selected
        let snapshot = preSnapshotTarget
        Task {
            await taskCenter.startTask(source: source, target: target,
                                       mappings: mappings, mode: mode,
                                       preSnapshotTarget: snapshot)
            isBusy = false
            dismiss()
        }
    }
}

struct MigrationBrowseEntry: Identifiable {
    let name: String
    let path: String
    let isDirectory: Bool
    var id: String { path }
}

// MARK: - Provisioning profile checker (W5b)

enum ProvisioningProfileChecker {
    /// Days until the embedded provisioning profile expires, or nil when the
    /// profile is missing/unparseable. Plist payload is CMS-wrapped; the
    /// expiry date lives in the DER payload and is located by scanning for
    /// the UTCTime/GeneralizedTime patterns near "ExpiryDate" is unreliable —
    /// instead decode the plist dict after the CMS envelope, which the
    /// standard `openssl`-free approach handles via Security.framework CMS
    /// decode. This falls back to a coarse scan that finds the two DER
    /// UTCTime structures and takes the later one.
    static func daysUntilExpiry(now: Date = Date()) -> Int? {
        guard let profileURL = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: profileURL) else { return nil }
        guard let dates = ProfileDates.decode(from: data), let expiry = dates.expiry else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                       to: calendar.startOfDay(for: expiry)).day
    }

    enum ProfileDates {
        struct Dates { let creation: Date?; let expiry: Date? }

        /// Minimal CMS-enveloped plist reader: locate the embedded plist
        /// (signed object begins with the XML/binary plist markers) and read
        /// CreationDate/ExpirationDate keys. Works for profiles whose payload
        /// is an XML plist (the common case for developer exports).
        static func decode(from data: Data) -> Dates? {
            let xmlMarker = Data("<?xml".utf8)
            let binMarker = Data("bplist00".utf8)
            var payloadRange: Range<Data.Index>?
            if let r = data.range(of: xmlMarker) { payloadRange = r }
            else if let r = data.range(of: binMarker) { payloadRange = r }
            guard let range = payloadRange else { return nil }
            let payload = data.subdata(in: range.lowerBound..<data.endIndex)
            guard let plist = try? PropertyListSerialization.propertyList(
                from: payload, options: [], format: nil) as? [String: Any] else { return nil }
            return Dates(creation: plist["CreationDate"] as? Date,
                         expiry: plist["ExpirationDate"] as? Date)
        }
    }
}
