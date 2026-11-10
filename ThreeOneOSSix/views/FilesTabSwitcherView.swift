import SwiftUI

struct FilesTabSwitcherView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @Binding var session: FilesTabSession
    @ObservedObject private var favoritesStore = FileFavoritesStore.shared
    @State private var renameTargetID: UUID?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(session.tabs) { tab in
                    Button {
                        session.selectTab(tab.id)
                        dismiss()
                    } label: {
                        tabRow(tab)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { tabActions(tab) }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            session.closeTab(tab.id)
                        } label: {
                            Label(language.text("browser.close_tab"), systemImage: "xmark")
                        }
                        Button {
                            beginRename(tab)
                        } label: {
                            Label(language.text("browser.rename_tab"), systemImage: "pencil")
                        }
                        .tint(AppTheme.accent)
                    }
                }
                if !favoritesStore.favorites.isEmpty {
                    Section {
                        ForEach(favoritesStore.favorites) { favorite in
                            Button {
                                session.openTab(navigationPath: [favorite.destination])
                                dismiss()
                            } label: {
                                FileFavoriteRow(favorite: favorite)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    favoritesStore.remove(path: favorite.path)
                                } label: {
                                    Label(
                                        language.text("browser.favorite_remove"),
                                        systemImage: "star.slash"
                                    )
                                }
                            }
                        }
                    } header: {
                        Text(language.text("browser.favorites"))
                    }
                }
            }
            .navigationTitle(language.text("browser.tabs"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("common.done")) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        session.openTab()
                        dismiss()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(language.text("browser.new_tab"))
                }
            }
            .alert(
                language.text("browser.rename_tab"),
                isPresented: renamePresentation
            ) {
                TextField(language.text("browser.tab_name"), text: $renameText)
                Button(language.text("common.cancel"), role: .cancel) {
                    renameTargetID = nil
                }
                Button(language.text("common.done")) {
                    if let renameTargetID {
                        session.renameTab(renameTargetID, to: renameText)
                    }
                    renameTargetID = nil
                }
            } message: {
                Text(language.text("browser.tab_name_message"))
            }
        }
    }

    private func tabRow(_ tab: FilesTabState) -> some View {
        HStack(spacing: 12) {
            Image(systemName: tab.id == session.selectedTabID ? "folder.fill" : "folder")
                .foregroundStyle(tab.id == session.selectedTabID ? AppTheme.accent : Color.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(tab.displayTitle(defaultTitle: language.text("browser.tabs_root")))
                    .font(.body.weight(tab.id == session.selectedTabID ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(tab.currentPath ?? language.text("browser.tabs_root_detail"))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
            if tab.id == session.selectedTabID {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func tabActions(_ tab: FilesTabState) -> some View {
        Button {
            beginRename(tab)
        } label: {
            Label(language.text("browser.rename_tab"), systemImage: "pencil")
        }
        Button {
            session.closeOtherTabs(keeping: tab.id)
        } label: {
            Label(language.text("browser.close_other_tabs"), systemImage: "square.on.square.dashed")
        }
        Button(role: .destructive) {
            session.closeTab(tab.id)
        } label: {
            Label(language.text("browser.close_tab"), systemImage: "xmark")
        }
    }

    private var renamePresentation: Binding<Bool> {
        Binding(
            get: { renameTargetID != nil },
            set: { if !$0 { renameTargetID = nil } }
        )
    }

    private func beginRename(_ tab: FilesTabState) {
        renameText = tab.displayTitle(defaultTitle: language.text("browser.tabs_root"))
        renameTargetID = tab.id
    }
}

struct FileFavoritesView: View {
    @Environment(\.appLanguage) private var language
    @ObservedObject private var store = FileFavoritesStore.shared

    var body: some View {
        List {
            if store.favorites.isEmpty {
                Text(language.text("browser.favorites_empty"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(store.favorites) { favorite in
                    NavigationLink(value: favorite.destination) {
                        FileFavoriteRow(favorite: favorite)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            store.remove(path: favorite.path)
                        } label: {
                            Label(
                                language.text("browser.favorite_remove"),
                                systemImage: "star.slash"
                            )
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(language.text("browser.favorites"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FileFavoriteRow: View {
    let favorite: FileFavorite

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "star.fill")
                .foregroundStyle(AppTheme.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(favorite.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(favorite.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .padding(.vertical, 3)
    }
}

extension FileFavorite {
    var destination: FileBrowserDestination {
        let container = FileFavoriteContainerRoot.containerPath(for: path) ?? path
        return FileBrowserDestination(
            containerPath: container,
            startPath: path,
            title: name,
            bundleID: nil
        )
    }
}
