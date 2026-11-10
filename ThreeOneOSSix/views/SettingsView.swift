import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var appState: AppState
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.english.rawValue
    @AppStorage(TabBarSelection.storageKey)
    private var tabBarSelectionRaw = TabBarSelection.defaultRaw
    @AppStorage(FeatureVisibility.developerModeStorageKey)
    private var developerModeEnabled = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        AppLogo()

                        VStack(alignment: .leading, spacing: 3) {
                            Text("3106").font(.headline)
                            Text(language.text("common.version", appVersion))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section(language.text("settings.language")) {
                    Picker(language.text("settings.language"), selection: $languageCode) {
                        ForEach(AppLanguage.allCases) { option in
                            Text(option.displayName).tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section {
                    NavigationLink {
                        BackupCenterView()
                    } label: {
                        Label(
                            language.text("backup.title"),
                            systemImage: "externaldrive.badge.timemachine"
                        )
                    }
                } header: {
                    Text(language.text("settings.backup"))
                }

                Section {
                    ForEach(AppSection.allCases) { section in
                        tabBarToggle(for: section)
                    }
                } header: {
                    Text(language.text("settings.tab_bar"))
                } footer: {
                    Text(
                        language.text(
                            "settings.tab_bar_footer",
                            Int64(selectedSections.count),
                            Int64(TabBarSelection.maxSections)
                        )
                    )
                }

                Section {
                    Toggle(isOn: $developerModeEnabled) {
                        Label(
                            language.text("settings.developer_mode"),
                            systemImage: "hammer.fill"
                        )
                    }
                } header: {
                    Text(language.text("dashboard.features"))
                } footer: {
                    Text(language.text("settings.developer_mode_footer"))
                }

                if WallpaperFeatureSupportPolicy.isSupported(
                    major: AppInfo.versionTuple.major
                ) {
                    Section {
                        NavigationLink {
                            WallpaperResetSettingsView()
                        } label: {
                            Label(
                                language.text("wallpaper.reset"),
                                systemImage: "arrow.counterclockwise"
                            )
                        }
                    } header: {
                        Text(language.text("tab.wallpapers"))
                    } footer: {
                        Text(language.text("wallpaper.reset_settings_footer"))
                    }
                }

                Section(language.text("common.device")) {
                    LabeledContent(language.text("dashboard.hardware_model"), value: AppInfo.displayMachineName)
                    LabeledContent(language.text("settings.ios_version"), value: "\(AppInfo.osVersion) (\(AppInfo.osBuild))")
                    LabeledContent(language.text("settings.access_backend"), value: SandboxAccess.backend.displayName)
                    LabeledContent(language.text("settings.app_group"), value: appGroupStatus)
                }

                Section {
                    HStack {
                        Text(language.text("settings.current_version"))
                        Spacer()
                        Text(language.text(appState.isSupported ? "settings.supported" : "settings.unsupported"))
                        .foregroundStyle(appState.isSupported ? Color.green : Color.red)
                    }
                    LabeledContent("iOS 17", value: ExploitSupportPolicy.verifiedIOS17Range)
                    LabeledContent("iOS 18", value: ExploitSupportPolicy.verifiedIOS18Range)
                    LabeledContent(
                        "iOS 26",
                        value: "\(ExploitSupportPolicy.verifiedIOS26BadQueryRange) · \(ExploitSupportPolicy.verifiedIOS26WorseQueryRange)"
                    )
                    LabeledContent("iOS 27", value: ExploitSupportPolicy.verifiedIOS27Range)
                } header: {
                    Text(language.text("settings.verified_versions"))
                } footer: {
                    Text(language.text("settings.supported_versions_footer"))
                }

                Section(language.text("settings.github")) {
                    if let destination = URL(string: "https://github.com/QuinnTang74/3106.git") {
                        Link(destination: destination) {
                            HStack(spacing: 12) {
                                Label("GitHub", systemImage: "link")
                                Spacer()
                                Text("QuinnTang74/3106")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                    }
                }
            }
            .tint(AppTheme.accent)
            .navigationTitle(language.text("settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(language.text("common.done")) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "AppReleaseDisplayVersion") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "1.0"
    }

    private var appGroupStatus: String {
        guard SandboxAccess.needsWorseQuery else { return "—" }
        return SandboxAccess.appGroup ?? language.text("settings.app_group_missing")
    }

    private var selectedSections: [AppSection] {
        TabBarSelection.sections(from: tabBarSelectionRaw)
    }

    private var wallpapersSupported: Bool {
        WallpaperFeatureSupportPolicy.isSupported(major: AppInfo.versionTuple.major)
    }

    @ViewBuilder
    private func tabBarToggle(for section: AppSection) -> some View {
        if section == .wallpapers && !wallpapersSupported {
            EmptyView()
        } else if section == .home {
            Toggle(isOn: .constant(true)) {
                Label(language.text(section.titleKey), systemImage: section.systemImage)
            }
            .disabled(true)
            .accessibilityValue(language.text("settings.tab_bar_fixed"))
        } else {
            Toggle(isOn: tabBarBinding(for: section)) {
                Label(language.text(section.titleKey), systemImage: section.systemImage)
            }
            .disabled(isTabBarToggleDisabled(section))
        }
    }

    private func isTabBarToggleDisabled(_ section: AppSection) -> Bool {
        if selectedSections.contains(section) { return false }
        guard selectedSections.count >= TabBarSelection.maxSections else { return false }
        return !(section == .cleaner && selectedSections.contains(.sources))
    }

    private func tabBarBinding(for section: AppSection) -> Binding<Bool> {
        Binding(
            get: { selectedSections.contains(section) },
            set: { isOn in
                var sections = selectedSections
                if isOn {
                    guard !sections.contains(section) else { return }
                    if sections.count >= TabBarSelection.maxSections {
                        guard section == .cleaner,
                              let sourcesIndex = sections.firstIndex(of: .sources) else {
                            return
                        }
                        sections.remove(at: sourcesIndex)
                    }
                    sections.append(section)
                } else {
                    guard section != .home else { return }
                    sections.removeAll { $0 == section }
                }
                tabBarSelectionRaw = TabBarSelection.encode(sections)
            }
        )
    }
}