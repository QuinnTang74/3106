import SwiftUI
import UIKit

struct AppDataBrowserView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var apps: [InstalledApp] = []
    @State private var unidentifiedApps: [InstalledApp] = []
    @State private var isLoading = false
    @State private var isResolving = false
    @State private var searchText = ""
    @State private var errorMessage: String?
    @State private var hasLoaded = false
    @State private var workspaceURL: URL?
    @Binding private var tabSession: FilesTabSession
    let onOpenSettings: () -> Void
    let onOpenLogs: () -> Void

    init(
        tabSession: Binding<FilesTabSession>,
        onOpenSettings: @escaping () -> Void = {},
        onOpenLogs: @escaping () -> Void = {}
    ) {
        _tabSession = tabSession
        self.onOpenSettings = onOpenSettings
        self.onOpenLogs = onOpenLogs
    }

    private var filteredApps: [InstalledApp] {
        guard !searchText.isEmpty else { return apps }
        let q = searchText.lowercased()
        return apps.filter {
            $0.name.lowercased().contains(q) || $0.bundleID.lowercased().contains(q)
        }
    }

    private var filteredUnidentifiedApps: [InstalledApp] {
        guard !searchText.isEmpty else { return unidentifiedApps }
        let q = searchText.lowercased()
        return unidentifiedApps.filter {
            $0.name.lowercased().contains(q) || $0.bundleID.lowercased().contains(q)
        }
    }

    private var overlayState: AppBrowserOverlayState {
        let total = apps.count + unidentifiedApps.count
        let filtered = filteredApps.count + filteredUnidentifiedApps.count
        if (isLoading || isResolving) && total == 0 { return .loading }
        if total == 0 { return .empty }
        if filtered == 0 { return .noResults }
        return .none
    }

    private var interfaceAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.20)
    }

    var body: some View {
        navigationContent(tabID: tabSession.selectedTabID)
            .id(tabSession.selectedTabID)
    }

    private func navigationContent(tabID: UUID) -> some View {
        NavigationStack(path: navigationPath(for: tabID)) {
            appList
            .navigationTitle(language.text("browser.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    FilesTabToolbarButton(session: $tabSession)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { reload(refreshLaunchServices: true) } label: {
                        if isResolving {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isResolving)
                    .accessibilityLabel(language.text("browser.retry"))
                }
                AppUtilityToolbar(
                    language: language,
                    onOpenSettings: onOpenSettings,
                    onOpenLogs: onOpenLogs
                )
            }
            .onAppear {
                if workspaceURL == nil {
                    workspaceURL = try? PatchWorkspaceService.documentsRootURL()
                    _ = try? PatchWorkspaceService.patchesRootURL()
                }
                if !hasLoaded {
                    hasLoaded = true
                    reload()
                }
            }
            .navigationDestination(for: FileBrowserDestination.self) { destination in
                if destination.startPath == destination.containerPath {
                    FileBrowserView(
                        containerPath: destination.containerPath,
                        title: destination.title,
                        bundleID: destination.bundleID,
                        filesTabSession: $tabSession
                    )
                } else {
                    FileBrowserView(
                        containerPath: destination.containerPath,
                        startPath: destination.startPath,
                        title: destination.title,
                        bundleID: destination.bundleID,
                        filesTabSession: $tabSession
                    )
                }
            }
        }
    }

    private func navigationPath(for tabID: UUID) -> Binding<[FileBrowserDestination]> {
        Binding(
            get: { tabSession.navigationPath(for: tabID) },
            set: { tabSession.setNavigationPath($0, for: tabID) }
        )
    }

    private var appList: some View {
        VStack(spacing: 0) {
            if horizontalSizeClass == .regular {
                FilesTabStrip(session: $tabSession)
            }
            AppSearchField(
                text: $searchText,
                prompt: language.text("browser.search"),
                clearLabel: language.text("common.clear")
            )
            Divider()
            appRows
        }
    }

    private var appRows: some View {
        List {
            if let workspaceURL {
                Section(language.text("browser.workspace")) {
                    let workspaceDestination = FileBrowserDestination(
                        containerPath: workspaceURL.path,
                        startPath: workspaceURL.path,
                        title: "3106",
                        bundleID: nil
                    )
                    NavigationLink(value: workspaceDestination) {
                        HStack(spacing: 10) {
                            AppRowIcon(systemName: "folder.fill")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("3106")
                                    .font(.subheadline.weight(.semibold))
                                Text(language.text("browser.workspace_subtitle"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .contextMenu {
                        openInNewTabButton(workspaceDestination)
                    }
                }
            }
            Section {
                ForEach(filteredApps) { app in
                    if app.containerPath.isEmpty {
                        appRow(app)
                    } else {
                        let appDestination = FileBrowserDestination(
                            containerPath: app.containerPath,
                            startPath: app.containerPath,
                            title: app.displayName,
                            bundleID: app.bundleID
                        )
                        NavigationLink(value: appDestination) {
                            appRow(app)
                        }
                        .contextMenu {
                            openInNewTabButton(appDestination)
                        }
                    }
                }
            } header: {
                HStack(spacing: 8) {
                    Text(language.text("browser.apps_count", Int64(filteredApps.count)))
                    Spacer()
                    if isResolving {
                        ProgressView()
                            .controlSize(.mini)
                        Text(language.text("browser.mha_scanning"))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(nil)
            }
            if !filteredUnidentifiedApps.isEmpty {
                Section {
                    ForEach(filteredUnidentifiedApps) { app in
                        let destination = FileBrowserDestination(
                            containerPath: app.containerPath,
                            startPath: app.containerPath,
                            title: app.displayName,
                            bundleID: nil,
                            readOnly: true
                        )
                        NavigationLink(value: destination) {
                            unidentifiedAppRow(app)
                        }
                        .contextMenu {
                            openInNewTabButton(destination)
                        }
                    }
                } header: {
                    Text(language.text(
                        "browser.unidentified_count",
                        Int64(filteredUnidentifiedApps.count)
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
                } footer: {
                    Text(language.text("browser.unidentified_footer"))
                }
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.defaultMinListRowHeight, 48)
        .scrollDismissesKeyboard(.interactively)
        .overlay {
            Group {
                switch overlayState {
                case .loading:
                    ProgressView(language.text("browser.loading"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .empty:
                    emptyView
                case .noResults:
                    searchEmptyView
                case .none:
                    EmptyView()
                }
            }
            .transition(.opacity)
            .animation(interfaceAnimation, value: overlayState)
        }
    }

    private func unidentifiedAppRow(_ app: InstalledApp) -> some View {
        HStack(spacing: 10) {
            BrowserAppIcon(app: app)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                Text(app.bundleID)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Text(language.text("browser.unidentified_badge"))
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12), in: Capsule())
        }
        .padding(.vertical, 2)
    }

    private func appRow(_ app: InstalledApp) -> some View {
        HStack(spacing: 10) {
            BrowserAppIcon(app: app)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                Text(app.bundleID)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if !app.version.isEmpty {
                Text(app.version)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 12))
    }

    private func openInNewTabButton(_ destination: FileBrowserDestination) -> some View {
        Button {
            tabSession.openTab(navigationPath: [destination])
        } label: {
            Label(language.text("browser.open_new_tab"), systemImage: "square.on.square")
        }
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: AppTheme.emptyIconSize, weight: .light))
                .foregroundStyle(.secondary)
            Text(errorMessage ?? language.text("browser.empty"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
            Button(language.text("browser.retry")) { reload(refreshLaunchServices: true) }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var searchEmptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: AppTheme.emptyIconSize, weight: .light))
                .foregroundStyle(.secondary)
            Text(language.text("browser.search_empty"))
                .font(.subheadline.weight(.medium))
            Text(language.text("browser.search_apps_empty_message"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func reload(refreshLaunchServices: Bool = false) {
        if refreshLaunchServices {
            ContainerStore.refreshLaunchServicesSnapshot()
        }
        isLoading = true
        isResolving = true
        errorMessage = nil
        let emptyMessage = language.text("browser.empty")
        DispatchQueue.global(qos: .userInitiated).async {
            let bundleMetadata = ContainerStore.applicationBundleMetadataCatalog()
            let apiApps = ContainerStore.applyingBundleMetadata(
                to: ContainerStore.installedAppsFromAPI(),
                catalog: bundleMetadata
            )
            if apiApps.isEmpty {
                log("browser: installed-app API unavailable; trying MCM class-2 enumeration...")
            }
            let dynamicIdentifiers = ContainerStore.dynamicAppIdentifiers()
            let mcmApps = ContainerStore.installedAppsFromMCM(
                identifiers: dynamicIdentifiers,
                bundleMetadata: bundleMetadata
            )
            let filesystemApps = ContainerStore.containersFromFilesystem()
            let baseIdentifiedApps = mcmApps + apiApps
            var result = ContainerDiscoveryMerger.merge(
                enumerated: filesystemApps,
                identified: baseIdentifiedApps,
                path: { $0.containerPath }
            )
            log("browser: merged api=\(apiApps.count), MCM=\(mcmApps.count), filesystem=\(filesystemApps.count) -> \(result.count)")
            result.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

            let preliminaryIdentified = result.filter {
                ContainerPresentationPolicy.isIdentified(bundleID: $0.bundleID)
            }
            let preliminaryUnidentified = result.filter {
                !ContainerPresentationPolicy.isIdentified(bundleID: $0.bundleID)
            }
            DispatchQueue.main.async {
                apps = preliminaryIdentified
                unidentifiedApps = preliminaryUnidentified
                isLoading = false
            }

            let launchServicesIdentifiers = ContainerStore.launchServicesStoreIdentifiers()
            let resolvedContainerCount = filesystemApps.reduce(0) { count, app in
                count + (UUID(uuidString: app.bundleID) == nil ? 1 : 0)
            }
            // The LaunchServices snapshot already names almost every
            // filesystem container. The MHA-C2 pass activates each candidate
            // through MCM and costs several seconds; only run it when the
            // filesystem list is mostly unidentified.
            let shouldScanMHA = filesystemApps.isEmpty
                || resolvedContainerCount * 4 < filesystemApps.count * 3
            var mhaApps: [InstalledApp] = []
            if shouldScanMHA {
                let mhaIdentifiers = MHAIdentifierCatalog.identifiers(
                    dynamic: dynamicIdentifiers,
                    installed: apiApps.map(\.bundleID),
                    research: ContainerStore.researchAppIdentifiers,
                    custom: bundleMetadata.keys.sorted(),
                    launchServices: launchServicesIdentifiers
                )
                log(
                    "browser: MHA catalog dynamic=\(dynamicIdentifiers.count), " +
                    "installed=\(apiApps.count), research=\(ContainerStore.researchAppIdentifiers.count), " +
                    "LaunchServices=\(launchServicesIdentifiers.count) -> \(mhaIdentifiers.count) candidates"
                )
                mhaApps = ContainerStore.installedAppsFromMHACandidates(
                    identifiers: mhaIdentifiers,
                    bundleMetadata: bundleMetadata
                ) { discoveredApps in
                    // Keep the filesystem fallback in the progressive result:
                    // replacing the list with identified-only entries made the
                    // browser visibly shrink while the MHA scan was running.
                    var progressiveResult = AppDataCatalogMerger.merge(
                        identified: discoveredApps + baseIdentifiedApps,
                        fallback: filesystemApps,
                        identifier: { $0.bundleID },
                        path: { $0.containerPath }
                    )
                    progressiveResult.sort {
                        $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                    }
                    let identified = progressiveResult.filter {
                        ContainerPresentationPolicy.isIdentified(bundleID: $0.bundleID)
                    }
                    let unidentified = progressiveResult.filter {
                        !ContainerPresentationPolicy.isIdentified(bundleID: $0.bundleID)
                    }
                    DispatchQueue.main.async {
                        apps = identified
                        unidentifiedApps = unidentified
                    }
                }
            } else {
                log(
                    "browser: skipping MHA scan — filesystem resolved " +
                        "\(resolvedContainerCount)/\(filesystemApps.count) containers"
                )
            }

            let allKnownApps = mhaApps + baseIdentifiedApps
            let identifiedPaths = Set(allKnownApps.map {
                ContainerDiscoveryMerger.canonicalPath($0.containerPath)
            })
            let unmatchedFilesystemApps = filesystemApps.filter {
                !identifiedPaths.contains(
                    ContainerDiscoveryMerger.canonicalPath($0.containerPath)
                )
            }
            let inferredFilesystemApps = ContainerStore.inferUnidentifiedApps(
                in: unmatchedFilesystemApps,
                knownApps: allKnownApps,
                launchServicesIdentifiers: Set(launchServicesIdentifiers)
            )
            result = AppDataCatalogMerger.merge(
                identified: allKnownApps,
                fallback: inferredFilesystemApps,
                identifier: { $0.bundleID },
                path: { $0.containerPath }
            )
            result.sort {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            let identified = result.filter {
                ContainerPresentationPolicy.isIdentified(bundleID: $0.bundleID)
            }
            let unidentified = result.filter {
                !ContainerPresentationPolicy.isIdentified(bundleID: $0.bundleID)
            }

            DispatchQueue.main.async {
                apps = identified
                unidentifiedApps = unidentified
                isLoading = false
                isResolving = false
                if result.isEmpty {
                    errorMessage = emptyMessage
                }
            }
        }
    }
}

private enum AppBrowserOverlayState: Equatable {
    case loading
    case empty
    case noResults
    case none
}

struct BrowserAppIcon: View {
    let app: InstalledApp
    @State private var resolvedIcon: UIImage?
    @State private var didRequestIcon = false

    init(app: InstalledApp) {
        self.app = app
        _resolvedIcon = State(initialValue: app.icon)
    }

    var body: some View {
        Group {
            if let resolvedIcon {
                Image(uiImage: resolvedIcon)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "app")
                    .font(.system(size: AppTheme.rowIconSize, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: AppTheme.appIconSize, height: AppTheme.appIconSize)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityHidden(true)
        .onAppear {
            guard resolvedIcon == nil, !didRequestIcon else { return }
            didRequestIcon = true
            let bundleID = app.bundleID
            DispatchQueue.global(qos: .utility).async {
                let icon = iconForBundleID(bundleID)
                DispatchQueue.main.async {
                    resolvedIcon = icon
                }
            }
        }
    }
}
