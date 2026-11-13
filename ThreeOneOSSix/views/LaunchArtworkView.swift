import SwiftUI
import PhotosUI
import CoreGraphics

/// Launch-artwork customization: replaces the app's SpringBoard snapshot
/// cache images with a user photo rendered at each snapshot's dimensions.
/// The app bundle is untouched; respring (or a launcher restart) refreshes
/// what the launcher shows.
struct LaunchArtworkView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss

    @State private var showPicker = false
    @State private var app: InstalledApp?
    @State private var groups: [LaunchArtworkService.SnapshotGroup] = []
    @State private var isLoadingGroups = false
    @State private var photoSelection: PhotosPickerItem?
    @State private var selectedImage: CGImage?
    @State private var riskShowing = false
    @State private var isRunning = false
    @State private var resultMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        List {
            appSection
            if let app = app {
                healthSection
                photoSection
            }
            if let message = resultMessage {
                Section {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                }
            }
        }
        .navigationTitle(language.text("launchartwork.title"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPicker) {
            LaunchArtworkAppPicker { picked in
                showPicker = false
                selectApp(picked)
            }
        }
        .sheet(isPresented: $riskShowing) {
            RiskConfirmationView(
                titleKey: "launchartwork.title",
                riskKey: "risk.launchArtwork",
                confirmActionKey: "risk.launchArtwork.confirm_action",
                onCancel: nil,
                onConfirm: { run() }
            )
        }
        .alert(language.text("launchartwork.error.title"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil }
        })) {
            Button(language.text("common.ok"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var appSection: some View {
        Section {
            Button {
                showPicker = true
            } label: {
                if let app = app {
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
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Label(language.text("launchartwork.pick_app"), systemImage: "square.grid.2x2")
                }
            }
        } header: {
            Text(language.text("launchartwork.section.app"))
        }
    }

    @ViewBuilder
    private var healthSection: some View {
        Section {
            if isLoadingGroups {
                HStack { ProgressView().controlSize(.small) }
            } else if groups.isEmpty {
                Text(language.text("launchartwork.no_snapshots"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                    VStack(alignment: .leading, spacing: 4) {
                        Text((group.directoryPath as NSString).lastPathComponent)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(language.text("launchartwork.group_files", Int64(group.files.count)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Button(role: .destructive) {
                            restore(group: group)
                        } label: {
                            Label(language.text("launchartwork.restore_group"), systemImage: "arrow.uturn.backward")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .disabled(isRunning)
                    }
                }
            }
        } header: {
            Text(language.text("launchartwork.section.snapshots"))
        } footer: {
            Text(language.text("launchartwork.snapshots_footer"))
        }
    }

    @ViewBuilder
    private var photoSection: some View {
        Section {
            PhotosPicker(selection: $photoSelection, matching: .images) {
                Label(language.text("launchartwork.pick_photo"), systemImage: "photo")
            }
            .disabled(groups.allSatisfy { !$0.isEditable })

            if selectedImage != nil {
                Button {
                    riskShowing = true
                } label: {
                    Label(language.text("launchartwork.apply"), systemImage: "paintbrush.fill")
                        .fontWeight(.semibold)
                }
                .disabled(isRunning)
            }
        } footer: {
            Text(language.text("launchartwork.apply_footer"))
        }
    }

    // MARK: - Actions

    private func selectApp(_ picked: InstalledApp) {
        app = picked
        groups = []
        resultMessage = nil
        isLoadingGroups = true
        let container = picked.containerPath
        let bundleID = picked.bundleID
        DispatchQueue.global(qos: .userInitiated).async {
            let grant = ContainerStore.grantContainerAccess(container)
            defer {
                if grant >= 0 { SandboxAccess.release(grant) }
            }
            let found = LaunchArtworkService.locateSnapshotGroups(
                containerPath: container, bundleID: bundleID
            )
            DispatchQueue.main.async {
                groups = found
                isLoadingGroups = false
            }
        }
    }

    private func restore(group: LaunchArtworkService.SnapshotGroup) {
        isRunning = true
        let target = group
        DispatchQueue.global(qos: .userInitiated).async {
            let count = LaunchArtworkService.restoreGroup(target)
            DispatchQueue.main.async {
                isRunning = false
                resultMessage = language.text("launchartwork.restored", Int64(count))
                selectApp(app ?? InstalledApp(bundleID: "", name: "", containerPath: "", version: "", icon: nil))
            }
        }
    }

    private func run() {
        guard let app = app, let image = selectedImage, let group = groups.first(where: { $0.isEditable }) else {
            return
        }
        isRunning = true
        let token = CancellationToken()
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let grant = ContainerStore.grantContainerAccess(app.containerPath)
                defer {
                    if grant >= 0 { SandboxAccess.release(grant) }
                }
                let count = try LaunchArtworkService.replaceAll(
                    with: image, in: group, token: token
                )
                DispatchQueue.main.async {
                    isRunning = false
                    resultMessage = language.text("launchartwork.done", Int64(count))
                }
            } catch {
                DispatchQueue.main.async {
                    isRunning = false
                    errorMessage = String(describing: error)
                }
            }
        }
    }
}

// MARK: - App picker (single pick)

struct LaunchArtworkAppPicker: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @State private var apps: [InstalledApp] = []
    @State private var hasLoaded = false
    let onPick: (InstalledApp) -> Void

    var body: some View {
        NavigationStack {
            List {
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
            }
            .navigationTitle(language.text("launchartwork.pick_app"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(language.text("common.cancel")) { dismiss() }
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
}
