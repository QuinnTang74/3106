import SwiftUI
import UniformTypeIdentifiers

/// CacheExtra field editor (GestaltX Field editor parity): search, add,
/// edit and remove CacheExtra entries across all eight plist types, with
/// plist import/export. Type handling is exact (GestaltValueKind), so a
/// Boolean stays a Boolean and a camera-zoom Real stays a Real on save.
struct GestaltFieldEditorView: View {
    @Environment(\.appLanguage) private var language
    @State private var entries: [GestaltFieldEntry] = []
    @State private var previewSnapshot: [GestaltEditPolicy.Field] = []
    @State private var searchText = ""
    @State private var isBusy = false
    @State private var activeAlert: FieldEditorAlert?
    @State private var editingEntry: GestaltFieldEntry?
    @State private var showAddSheet = false
    @State private var showImporter = false
    @State private var hasLoaded = false
    @State private var importSummary: ImportSummary?

    private static let plistType = UTType(filenameExtension: "plist") ?? .data

    var body: some View {
        List {
            BackendNoticeBanner()
            summarySection
            entriesSection
        }
        .searchable(
            text: .init(get: { searchText }, set: { searchText = $0 }),
            placement: .navigationBarDrawer(displayMode: .always)
        )
        .navigationTitle(language.text("gestalt.field.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showAddSheet = true
                    } label: {
                        Label(language.text("gestalt.field.add"), systemImage: "plus")
                    }
                    Button {
                        exportPlist()
                    } label: {
                        Label(language.text("gestalt.field.export"), systemImage: "square.and.arrow.up")
                    }
                    Button {
                        showImporter = true
                    } label: {
                        Label(language.text("gestalt.field.import"), systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(isBusy)
            }
            ToolbarItem(placement: .navigationBarLeading) {
                if isBusy {
                    ProgressView()
                }
            }
        }
        .onAppear {
            guard !hasLoaded else { return }
            hasLoaded = true
            reload()
        }
        .refreshable { reload() }
        .sheet(item: $editingEntry) { entry in
            GestaltFieldEditSheet(entry: entry) { key, kindText, text in
                saveEntry(key: key, kindText: kindText, text: text)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            GestaltFieldEditSheet(entry: nil) { key, kindText, text in
                saveEntry(key: key, kindText: kindText, text: text)
            }
        }
        .sheet(isPresented: $showImporter) {
            FileDocumentPicker(
                allowedContentTypes: [Self.plistType, .data],
                copiesSelectedDocument: true,
                allowsMultipleSelection: false,
                onSelection: { result in
                    showImporter = false
                    if case .success(let urls) = result, let url = urls.first {
                        importPlist(from: url)
                    }
                },
                onCancel: { showImporter = false }
            )
            .ignoresSafeArea()
        }
        .alert(item: $activeAlert, content: alertContent)
    }

    private var summarySection: some View {
        Section {
            LabeledContent(language.text("gestalt.field.count")) {
                Text("\(entries.count)").monospacedDigit()
            }
        } header: {
            Label(language.text("gestalt.field.title"), systemImage: "list.bullet.rectangle")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(language.text("gestalt.field.footer"))
                if let importSummary {
                    Text(language.text(
                        "gestalt.field.import_summary",
                        importSummary.overwritten,
                        importSummary.skipped,
                        importSummary.preserved
                    ))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var entriesSection: some View {
        Section {
            if entries.isEmpty && !isBusy {
                Text(language.text("gestalt.field.empty"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(filteredEntries) { entry in
                Button {
                    editingEntry = entry
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.key)
                            .font(.system(.footnote, design: .monospaced).weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                        HStack(spacing: 6) {
                            Text(language.text("gestalt.field.kind.\(entry.kind.rawValue.lowercased())"))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppTheme.accent)
                            Text(entry.preview)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                .contextMenu {
                    Button(role: .destructive) {
                        removeEntry(entry)
                    } label: {
                        Label(language.text("gestalt.field.remove"), systemImage: "trash")
                    }
                }
            }
        } header: {
            Text(language.text("gestalt.field.entries"))
        }
    }

    /// GestaltX #136: the preview snapshot is built once by reload(); search
    /// only filters it, so typing never recomputes previews for plist entries.
    private var filteredEntries: [GestaltFieldEntry] {
        let matchedKeys = Set(
            GestaltEditPolicy.filtered(previewSnapshot, query: searchText).map(\.key)
        )
        return entries.filter { matchedKeys.contains($0.key) }
    }

    // MARK: - Data

    private func reload() {
        isBusy = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let root = try GestaltPlistIO.readRoot()
                let cacheExtra = (root["CacheExtra"] as? [String: Any]) ?? [:]
                let loaded = cacheExtra
                    .map { key, value in
                        GestaltFieldEntry(
                            key: key,
                            kind: GestaltValueKind.detect(value),
                            rawText: GestaltValueKind.render(value)
                        )
                    }
                    .sorted { $0.key < $1.key }
                let snapshot = loaded.map {
                    GestaltEditPolicy.Field(key: $0.key, preview: $0.preview)
                }
                DispatchQueue.main.async {
                    entries = loaded
                    previewSnapshot = snapshot
                    isBusy = false
                }
            } catch {
                DispatchQueue.main.async {
                    isBusy = false
                    activeAlert = .message(language.text("gestalt.error.unreadable"))
                }
            }
        }
    }

    private func saveEntry(key: String, kindText: String, text: String) {
        guard let kind = GestaltValueKind(rawValue: kindText) else { return }
        isBusy = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Exclusive across read→mutate→write (shared Gestalt cache).
                try GestaltPlistIO.withExclusiveAccess {
                    var root = try GestaltPlistIO.readRoot()
                    guard var cacheExtra = root["CacheExtra"] as? [String: Any] else {
                        throw GestaltPresetError.missingCacheExtra
                    }
                    let value = try kind.parse(text)
                    cacheExtra[key] = value
                    root["CacheExtra"] = cacheExtra
                    try GestaltPlistIO.writeRoot(root, reason: "field-edit:\(key)")
                    GestaltExplicitEdits.record(key)
                }
                DispatchQueue.main.async {
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

    private func removeEntry(_ entry: GestaltFieldEntry) {
        isBusy = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try GestaltPlistIO.withExclusiveAccess {
                    var root = try GestaltPlistIO.readRoot()
                    guard var cacheExtra = root["CacheExtra"] as? [String: Any] else {
                        throw GestaltPresetError.missingCacheExtra
                    }
                    cacheExtra.removeValue(forKey: entry.key)
                    root["CacheExtra"] = cacheExtra
                    try GestaltPlistIO.writeRoot(root, reason: "field-remove:\(entry.key)")
                }
                DispatchQueue.main.async {
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

    private func exportPlist() {
        isBusy = true
        DispatchQueue.global(qos: .utility).async {
            do {
                let root = try GestaltPlistIO.readRoot()
                let data = try PropertyListSerialization.data(
                    fromPropertyList: root, format: .xml, options: 0
                )
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("MobileGestalt-\(Int(Date().timeIntervalSince1970)).plist")
                try data.write(to: url, options: .atomic)
                DispatchQueue.main.async {
                    isBusy = false
                    let activity = UIActivityViewController(
                        activityItems: [url],
                        applicationActivities: nil
                    )
                    // iPad requires a popover source or presentation crashes.
                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let root = scene.keyWindow?.rootViewController {
                        activity.popoverPresentationController?.sourceView = root.view
                        activity.popoverPresentationController?.sourceRect = CGRect(
                            x: root.view.bounds.midX, y: root.view.bounds.maxY - 8,
                            width: 1, height: 1
                        )
                        root.present(activity, animated: true)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    isBusy = false
                    activeAlert = .message(language.errorText(error))
                }
            }
        }
    }

    private func importPlist(from url: URL) {
        isBusy = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let secured = url.startAccessingSecurityScopedResource()
                defer { if secured { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                guard
                    let imported = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                    imported["CacheExtra"] is [String: Any]
                else {
                    throw GestaltPresetError.invalidPlist
                }
                // GestaltX #138: the import is a patch. Read, merge and write
                // under one lock so the four Gestalt pipelines cannot interleave
                // a stale root between our read and the verified write.
                let merged = try GestaltPlistIO.withExclusiveAccess {
                    let snapshot = try GestaltPlistIO.readRootWithFormat()
                    let result = try GestaltPlistMerge.mergingFieldImport(
                        current: snapshot.root, imported: imported
                    )
                    try GestaltPlistIO.writeRoot(
                        result.root, reason: "field-import", format: snapshot.format
                    )
                    return result
                }
                DispatchQueue.main.async {
                    importSummary = .init(
                        overwritten: merged.overwritten.count,
                        skipped: merged.skipped.count,
                        preserved: merged.preserved
                    )
                    SoundEffects.play(.success)
                    reload()
                }
            } catch {
                DispatchQueue.main.async {
                    SoundEffects.play(.failure)
                    activeAlert = .message(language.errorText(fieldImportError(error)))
                    isBusy = false
                }
            }
        }
    }

    private func fieldImportError(_ error: Error) -> Error {
        guard let mergeError = error as? GestaltMergeError else { return error }
        switch mergeError {
        case .missingCacheExtra:
            return GestaltPresetError.missingCacheExtra
        case .layoutMismatch:
            return GestaltFieldImportError.layoutMismatch
        case .unsupportedValueType:
            return GestaltPresetError.invalidPlist
        }
    }

    private func alertContent(for alert: FieldEditorAlert) -> Alert {
        Alert(
            title: Text(language.text("gestalt.field.title")),
            message: Text(alert.message),
            dismissButton: .default(Text(language.text("common.ok")))
        )
    }
}

// MARK: - Supporting types

private struct ImportSummary {
    let overwritten: Int
    let skipped: Int
    let preserved: Int
}

private enum GestaltFieldImportError: LocalizedError {
    case layoutMismatch

    var errorDescription: String? { "gestalt.error.layout_mismatch" }
}

struct GestaltFieldEntry: Identifiable {
    let key: String
    let kind: GestaltValueKind
    let rawText: String

    var id: String { key }
    var preview: String {
        switch kind {
        case .data, .array, .dictionary:
            return rawText.count > 48 ? String(rawText.prefix(48)) + "…" : rawText
        default:
            return rawText
        }
    }
}

enum FieldEditorAlert: Identifiable {
    case message(String)

    var message: String {
        if case .message(let text) = self { return text }
        return ""
    }

    var id: String { "msg-\(message)" }
}

/// Edit sheet: key + kind + value text. For an existing entry the kind is
/// detected and shown; changing it re-parses the text as the new kind.
struct GestaltFieldEditSheet: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss

    let entry: GestaltFieldEntry?
    let onSave: (String, String, String) -> Void

    @State private var keyText: String
    @State private var kindText: String
    @State private var valueText: String

    init(
        entry: GestaltFieldEntry?,
        onSave: @escaping (String, String, String) -> Void
    ) {
        self.entry = entry
        self.onSave = onSave
        _keyText = State(initialValue: entry?.key ?? "")
        _kindText = State(initialValue: entry?.kind.rawValue ?? GestaltValueKind.boolean.rawValue)
        _valueText = State(initialValue: entry?.rawText ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(language.text("gestalt.field.edit_key")) {
                    TextField("h63QSdBCiT/z0WU6rdQv6Q", text: $keyText)
                        .font(.system(.footnote, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section(language.text("gestalt.field.edit_kind")) {
                    Picker(language.text("gestalt.field.edit_kind"), selection: $kindText) {
                        ForEach(GestaltValueKind.allCases) { kind in
                            Text(language.text("gestalt.field.kind.\(kind.rawValue.lowercased())"))
                                .tag(kind.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Section(language.text("gestalt.field.edit_value")) {
                    TextEditor(text: $valueText)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 96)
                }
                Section {
                    Text(language.text("gestalt.field.backup_note"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(language.text(entry == nil ? "gestalt.field.add" : "gestalt.field.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(language.text("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text("common.save")) {
                        onSave(keyText, kindText, valueText)
                        dismiss()
                    }
                    .disabled(keyText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
