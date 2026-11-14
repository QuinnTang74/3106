import SwiftUI
import UniformTypeIdentifiers

/// Notification sound replacement page (GestaltX App Audio Library parity):
/// maintain the per-app notification-sound path table, pick custom audio,
/// replace with an automatic backup, and restore from the replace record.
/// Not-listed apps are added through manual path entry — no pairing or
/// capture tunnel.
struct NotificationSoundView: View {
    @Environment(\.appLanguage) private var language
    @State private var targets: [NotificationSoundService.SoundTarget] = []
    @State private var installed: [NotificationSoundService.InstalledSound] = []
    @State private var isBusy = false
    @State private var activeAlert: NotificationSoundAlert?
    @State private var pendingRisk: NotificationSoundService.SoundTarget?
    @State private var pickingTarget: NotificationSoundService.SoundTarget?
    @State private var showAddSheet = false
    @State private var addBundleID = ""
    @State private var addAppName = ""
    @State private var addPath = ""
    @State private var hasLoaded = false

    var body: some View {
        List {
            targetsSection
            installedSection
        }
        .navigationTitle(language.text("notification.sound.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    addBundleID = ""
                    addAppName = ""
                    addPath = ""
                    showAddSheet = true
                } label: {
                    Label(language.text("notification.sound.add"), systemImage: "plus")
                }
            }
        }
        .refreshable { reload() }
        .onAppear {
            guard !hasLoaded else { return }
            hasLoaded = true
            reload()
        }
        .alert(item: $activeAlert, content: alertContent)
        .sheet(item: $pendingRisk) { target in
            RiskConfirmationView(
                titleKey: "notification.sound.risk.title",
                riskKey: "notification.sound.risk",
                confirmActionKey: "notification.sound.risk.confirm",
                onCancel: { pendingRisk = nil },
                onConfirm: {
                    pendingRisk = nil
                    pickingTarget = target
                }
            )
        }
        .sheet(item: $pickingTarget) { target in
            FileDocumentPicker(
                allowedContentTypes: NotificationSoundService.pickerContentTypes,
                allowsMultipleSelection: false,
                onSelection: { result in
                    pickingTarget = nil
                    handleSelection(result: result, target: target)
                },
                onCancel: { pickingTarget = nil }
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showAddSheet) {
            addSheet
        }
    }

    // MARK: - Sections

    private var targetsSection: some View {
        Section {
            if targets.isEmpty {
                Text(language.text("notification.sound.empty"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(targets) { target in
                VStack(alignment: .leading, spacing: 3) {
                    Text(target.appName.isEmpty ? target.bundleID : target.appName)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(target.relativePath)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                .swipeActions {
                    Button(role: .destructive) {
                        NotificationSoundService.deleteTarget(id: target.id)
                        reload()
                    } label: {
                        Label(language.text("common.delete"), systemImage: "trash")
                    }
                    Button {
                        pendingRisk = target
                    } label: {
                        Label(language.text("notification.sound.replace"), systemImage: "speaker.wave.2.fill")
                    }
                    .tint(AppTheme.accent)
                }
                .contextMenu {
                    Button {
                        pendingRisk = target
                    } label: {
                        Label(language.text("notification.sound.replace"), systemImage: "speaker.wave.2.fill")
                    }
                }
            }
        } header: {
            Label(language.text("notification.sound.targets_header"), systemImage: "speaker.wave.2")
        } footer: {
            Text(language.text("notification.sound.targets_footer"))
        }
    }

    private var installedSection: some View {
        Section {
            if installed.isEmpty {
                Text(language.text("notification.sound.installed_empty"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(installed) { item in
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.target.appName.isEmpty ? item.target.bundleID : item.target.appName)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(item.record.targetPath)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .swipeActions {
                    Button {
                        restore(item)
                    } label: {
                        Label(language.text("notification.sound.restore"), systemImage: "arrow.uturn.backward.circle")
                    }
                    .tint(AppTheme.accent)
                    .disabled(isBusy || item.record.backupPath == nil)
                }
            }
        } header: {
            Label(language.text("notification.sound.installed_header"), systemImage: "music.note")
        } footer: {
            Text(language.text("notification.sound.installed_footer"))
        }
    }

    private var addSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(language.text("notification.sound.field_bundle"), text: $addBundleID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField(language.text("notification.sound.field_name"), text: $addAppName)
                    TextField(language.text("notification.sound.field_path"), text: $addPath)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text(language.text("notification.sound.add_footer"))
                }
            }
            .navigationTitle(language.text("notification.sound.add"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("common.cancel")) { showAddSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("common.save")) {
                        let bundleID = addBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
                        let path = addPath.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !bundleID.isEmpty, !path.isEmpty else { return }
                        NotificationSoundService.saveTarget(
                            bundleID: bundleID,
                            appName: addAppName.trimmingCharacters(in: .whitespacesAndNewlines),
                            relativePath: path
                        )
                        showAddSheet = false
                        reload()
                    }
                    .disabled(
                        addBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || addPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
        }
    }

    // MARK: - Actions

    private func reload() {
        DispatchQueue.global(qos: .userInitiated).async {
            let loadedTargets = NotificationSoundService.targets()
            let loadedInstalled = NotificationSoundService.installedSounds()
            DispatchQueue.main.async {
                targets = loadedTargets
                installed = loadedInstalled
            }
        }
    }

    /// The picker runs after the risk confirmation; the caller resolves the
    /// device-specific absolute paths from the container at install time.
    private func handleSelection(
        result: Result<[URL], Error>,
        target: NotificationSoundService.SoundTarget
    ) {
        switch result {
        case .failure(let error):
            activeAlert = .message(language.errorText(error))
        case .success(let urls):
            guard let source = urls.first else { return }
            guard NotificationSoundPolicy.acceptsSourceExtension(source.pathExtension) else {
                SoundEffects.play(.failure)
                activeAlert = .message(language.text("notification.sound.error.extension"))
                return
            }
            let containerRoot = ContainerStore.resolveAppContainerPath(bundleID: target.bundleID)
            guard let containerRoot,
                  let resolved = resolveTargetPath(target: target, containerRoot: containerRoot) else {
                SoundEffects.play(.failure)
                activeAlert = .message(language.text("notification.sound.error.container"))
                return
            }
            isBusy = true
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    _ = try NotificationSoundService.install(
                        target: target,
                        absoluteTargetPath: resolved,
                        containerRoot: containerRoot,
                        sourceURL: source,
                        backupRequested: true
                    )
                    NotificationSoundService.saveTarget(
                        bundleID: target.bundleID,
                        appName: target.appName,
                        relativePath: target.relativePath
                    )
                    DispatchQueue.main.async {
                        isBusy = false
                        SoundEffects.play(.success)
                        reload()
                    }
                } catch {
                    DispatchQueue.main.async {
                        isBusy = false
                        SoundEffects.play(.failure)
                        activeAlert = .message(language.errorText(error))
                    }
                }
            }
        }
    }

    private func resolveTargetPath(
        target: NotificationSoundService.SoundTarget, containerRoot: String
    ) -> String? {
        let candidate = (containerRoot as NSString)
            .appendingPathComponent(target.relativePath)
        guard FileManager.default.fileExists(atPath: candidate) else { return nil }
        return candidate
    }

    private func restore(_ item: NotificationSoundService.InstalledSound) {
        isBusy = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try FileReplaceService.restore(record: item.record)
                DispatchQueue.main.async {
                    isBusy = false
                    SoundEffects.play(.success)
                    reload()
                }
            } catch {
                DispatchQueue.main.async {
                    isBusy = false
                    SoundEffects.play(.failure)
                    activeAlert = .message(language.errorText(error))
                }
            }
        }
    }

    private func alertContent(for alert: NotificationSoundAlert) -> Alert {
        Alert(
            title: Text(language.text("notification.sound.title")),
            message: Text(alert.message),
            dismissButton: .default(Text(language.text("common.ok")))
        )
    }
}

enum NotificationSoundAlert: Identifiable {
    case message(String)

    var message: String {
        if case .message(let text) = self { return text }
        return ""
    }

    var id: String { "notification-sound-\(message)" }
}
