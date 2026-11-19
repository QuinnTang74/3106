import SwiftUI
import UniformTypeIdentifiers

struct FileInfoView: View {
    @Environment(\.appLanguage) private var language
    let path: String

    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var values: [InfoRow] = []
    @State private var mode: Int?
    @State private var isSymbolicLink = false
    @State private var isApplying = false
    @State private var notice: Notice?

    private struct InfoRow: Identifiable {
        let id = UUID()
        let title: String
        let value: String
    }

    private struct Notice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    var body: some View {
        List {
            if isLoading {
                HStack {
                    ProgressView()
                    Text(language.text("fileinfo.loading"))
                        .foregroundStyle(.secondary)
                }
            } else if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else {
                Section(language.text("fileinfo.section.general")) {
                    ForEach(values) { row in
                        LabeledContent(row.title) {
                            Text(row.value)
                                .font(.footnote.monospaced())
                                .textSelection(.enabled)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
                if let mode {
                    permissionSection(mode: mode)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(language.text("fileinfo.title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .alert(item: $notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text(language.text("common.ok")))
            )
        }
    }

    @ViewBuilder
    private func permissionSection(mode: Int) -> some View {
        Section {
            LabeledContent(language.text("fileinfo.permissions")) {
                HStack(spacing: 8) {
                    Text(PermissionPolicy.octalString(mode))
                    Text(PermissionPolicy.symbolicString(mode))
                        .foregroundStyle(.secondary)
                }
                .font(.footnote.monospaced())
                .textSelection(.enabled)
            }
        } header: {
            Text(language.text("fileinfo.section.permissions"))
        } footer: {
            if isSymbolicLink {
                Text(language.text("fileinfo.permissions.symlink"))
            } else if PermissionPolicy.isReadOnly(mode) {
                // The interesting state, not just a static caption: a read-only
                // file is exactly what a locked-down app container looks like.
                Text(language.text("fileinfo.permissions.read_only"))
            } else {
                Text(language.text("fileinfo.permissions.footer"))
            }
        }

        if !isSymbolicLink {
            Section(language.text("fileinfo.permissions.presets")) {
                ForEach(PermissionPolicy.presets, id: \.self) { preset in
                    let current = PermissionPolicy.isCurrent(mode, preset: preset)
                    Button {
                        apply(preset: preset)
                    } label: {
                        HStack {
                            Text(PermissionPolicy.presetLabel(preset))
                                .font(.footnote.monospaced())
                            Spacer()
                            if current {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(current || isApplying)
                }
            }
        }
    }

    // MARK: - Load

    private func load() {
        isLoading = true
        errorMessage = nil
        let path = path
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let url = URL(fileURLWithPath: path)
                let resourceValues = try url.resourceValues(forKeys: [
                    .fileSizeKey,
                    .creationDateKey,
                    .contentModificationDateKey,
                    .isDirectoryKey,
                    .isSymbolicLinkKey,
                    .isRegularFileKey,
                    .contentTypeKey,
                ])
                let attributes = try FileManager.default.attributesOfItem(atPath: path)
                let size = resourceValues.fileSize ?? (attributes[.size] as? NSNumber)?.intValue ?? 0
                let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
                let type = resourceValues.contentType?.localizedDescription
                    ?? (resourceValues.isDirectory == true
                        ? language.text("fileinfo.type.folder")
                        : language.text("fileinfo.type.file"))

                var rows: [InfoRow] = [
                    InfoRow(title: language.text("fileinfo.name"), value: url.lastPathComponent),
                    InfoRow(title: language.text("fileinfo.path"), value: path),
                    InfoRow(title: language.text("fileinfo.type"), value: type),
                    InfoRow(
                        title: language.text("fileinfo.size"),
                        value: ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
                    ),
                ]
                if let modified = resourceValues.contentModificationDate {
                    rows.append(InfoRow(
                        title: language.text("fileinfo.modified"),
                        value: modified.formatted(date: .abbreviated, time: .standard)
                    ))
                }
                if let created = resourceValues.creationDate {
                    rows.append(InfoRow(
                        title: language.text("fileinfo.created"),
                        value: created.formatted(date: .abbreviated, time: .standard)
                    ))
                }
                rows.append(InfoRow(
                    title: language.text("fileinfo.permissions"),
                    value: PermissionPolicy.octalString(permissions)
                ))
                if let owner = attributes[.ownerAccountName] as? String {
                    rows.append(InfoRow(title: language.text("fileinfo.owner"), value: owner))
                }
                if let group = attributes[.groupOwnerAccountName] as? String {
                    rows.append(InfoRow(title: language.text("fileinfo.group"), value: group))
                }
                if resourceValues.isSymbolicLink == true {
                    rows.append(InfoRow(
                        title: language.text("fileinfo.symlink"),
                        value: language.text("common.yes")
                    ))
                }

                let isLink = resourceValues.isSymbolicLink == true
                DispatchQueue.main.async {
                    values = rows
                    mode = permissions
                    isSymbolicLink = isLink
                    isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Apply

    /// Preconditions the editor relies on:
    /// - Never follow a symlink. chmod on a link path changes the target, which
    ///   from this screen would look like editing the link's own mode.
    /// - Snapshot before writing, so a mistyped `0444` on a live container file
    ///   is reversible from the backup list.
    private func apply(preset: Int) {
        guard !isApplying else { return }
        isApplying = true
        let path = path
        let targetMode = preset

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                var info = stat()
                guard lstat(path, &info) == 0 else {
                    throw PermissionEditError.missing
                }
                guard (info.st_mode & S_IFMT) != S_IFLNK else {
                    throw PermissionEditError.symbolicLink
                }

                let target = URL(fileURLWithPath: path)
                try BackupCenter.shared.createVersionSnapshot(
                    target: target,
                    feature: .file,
                    reason: "before chmod \(PermissionPolicy.octalString(targetMode))"
                )

                let parent = (path as NSString).deletingLastPathComponent
                try SandboxAccess.withGrant(directory: parent, writable: true) {
                    try FileManager.default.setAttributes(
                        [.posixPermissions: NSNumber(value: targetMode & 0o777)],
                        ofItemAtPath: path
                    )
                }

                // Read back: setAttributes returning cleanly does not prove the
                // mode landed, and a wrong mode here is invisible until an app
                // fails to open its own container.
                let attributes = try FileManager.default.attributesOfItem(atPath: path)
                let applied = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
                guard PermissionPolicy.masked(applied) == PermissionPolicy.masked(targetMode) else {
                    throw PermissionEditError.verifyFailed(
                        expected: PermissionPolicy.octalString(targetMode),
                        actual: PermissionPolicy.octalString(applied)
                    )
                }

                DispatchQueue.main.async {
                    isApplying = false
                    mode = applied
                    values = values.map { row in
                        row.title == language.text("fileinfo.permissions")
                            ? InfoRow(title: row.title, value: PermissionPolicy.octalString(applied))
                            : row
                    }
                    notice = Notice(
                        title: language.text("fileinfo.permissions.applied_title"),
                        message: language.text(
                            "fileinfo.permissions.applied_message",
                            PermissionPolicy.octalString(applied)
                        )
                    )
                }
            } catch {
                DispatchQueue.main.async {
                    isApplying = false
                    notice = Notice(
                        title: language.text("fileinfo.permissions.failed_title"),
                        message: localizedDescription(of: error)
                    )
                }
            }
        }
    }

    private func localizedDescription(of error: Error) -> String {
        if let edit = error as? PermissionEditError {
            return edit.errorDescription ?? String(describing: error)
        }
        return language.errorText(error)
    }
}

private enum PermissionEditError: Error, LocalizedError {
    case missing
    case symbolicLink
    case verifyFailed(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .missing:
            return "The file no longer exists."
        case .symbolicLink:
            return "Symbolic links are not supported: changing their mode would "
                + "modify the file they point at."
        case .verifyFailed(let expected, let actual):
            return "The mode did not stick: asked for \(expected), found \(actual)."
        }
    }
}