import SwiftUI

/// The landing page: a local feature hub instead of a remote repository feed.
/// Everything that used to occupy its own tab bar slot (market, sources,
/// installed patches) is reachable from here, keeping the bottom bar at five
/// fixed destinations.
struct FeatureHubView: View {
    @Environment(\.appLanguage) private var language
    let onSelectTab: (AppSection) -> Void
    let onOpenSettings: () -> Void
    let onOpenLogs: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent(language.text("home.version"), value: appVersion)
                    LabeledContent(
                        language.text("home.backend"),
                        value: SandboxAccess.backend.displayName
                    )
                    if SandboxAccess.needsWorseQuery {
                        LabeledContent(
                            language.text("home.app_group"),
                            value: appGroupText
                        )
                        if SandboxAccess.appGroup == nil {
                            Text(language.text("home.app_group_warning"))
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                } header: {
                    Text(language.text("home.status"))
                }

                Section {
                    NavigationLink {
                        PatchProjectsView(
                            onOpenSettings: onOpenSettings,
                            onOpenLogs: onOpenLogs
                        )
                    } label: {
                        card(
                            "home.card.patches",
                            detail: "home.card.patches_detail",
                            icon: "square.stack.3d.up.fill"
                        )
                    }

                    NavigationLink {
                        RepositoryNewView(
                            onOpenSettings: onOpenSettings,
                            onOpenLogs: onOpenLogs
                        )
                    } label: {
                        card(
                            "home.card.market",
                            detail: "home.card.market_detail",
                            icon: "sparkles"
                        )
                    }

                    NavigationLink {
                        RepositorySourcesView(
                            onOpenSettings: onOpenSettings,
                            onOpenLogs: onOpenLogs
                        )
                    } label: {
                        card(
                            "home.card.sources",
                            detail: "home.card.sources_detail",
                            icon: "shippingbox.fill"
                        )
                    }
                } header: {
                    Text(language.text("home.section.apps"))
                }

                Section {
                    Button {
                        onSelectTab(.files)
                    } label: {
                        card(
                            "home.card.files",
                            detail: "home.card.files_detail",
                            icon: "folder.fill"
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        onSelectTab(.search)
                    } label: {
                        card(
                            "home.card.search",
                            detail: "home.card.search_detail",
                            icon: "magnifyingglass"
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        onSelectTab(.cleaner)
                    } label: {
                        card(
                            "home.card.cleaner",
                            detail: "home.card.cleaner_detail",
                            icon: "sparkles"
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        onSelectTab(.wallpapers)
                    } label: {
                        card(
                            "home.card.wallpapers",
                            detail: "home.card.wallpapers_detail",
                            icon: "photo.on.rectangle.angled"
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        BackupCenterView()
                    } label: {
                        card(
                            "home.card.backups",
                            detail: "home.card.backups_detail",
                            icon: "externaldrive.fill"
                        )
                    }
                } header: {
                    Text(language.text("home.section.data"))
                }

                Section {
                    NavigationLink {
                        LogView()
                    } label: {
                        card(
                            "home.card.logs",
                            detail: "home.card.logs_detail",
                            icon: "apple.terminal.fill"
                        )
                    }

                    Button(action: onOpenSettings) {
                        card(
                            "home.card.settings",
                            detail: "home.card.settings_detail",
                            icon: "gear"
                        )
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text(language.text("home.section.about"))
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(language.text("tab.features"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                AppUtilityToolbar(
                    language: language,
                    onOpenSettings: onOpenSettings,
                    onOpenLogs: onOpenLogs
                )
            }
        }
    }

    private func card(
        _ titleKey: String,
        detail: String,
        icon: String
    ) -> some View {
        HStack(spacing: 12) {
            AppRowIcon(systemName: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(language.text(titleKey))
                    .foregroundStyle(.primary)
                Text(language.text(detail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    private var appGroupText: String {
        SandboxAccess.appGroup ?? language.text("home.app_group_missing")
    }
}