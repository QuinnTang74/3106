import SwiftUI

/// Per-mapping target path editor. Validation mirrors the engine's joinRoot:
/// no `..`, no absolute paths, no escaping the target container root.
struct MigrationMappingView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss

    @State var mappings: [MigrationMapping]
    let onDone: ([MigrationMapping]) -> Void

    var body: some View {
        List {
            ForEach($mappings) { $mapping in
                VStack(alignment: .leading, spacing: 8) {
                    Text(mapping.sourceRelativePath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    TextField(language.text("migration.mapping.target_field"), text: $mapping.targetRelativePath)
                        .font(.caption.monospaced())
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if let error = validationError(for: mapping.targetRelativePath) {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .navigationTitle(language.text("migration.mapping.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(language.text("common.done")) {
                    onDone(mappings)
                    dismiss()
                }
                .disabled(mappings.contains { validationError(for: $0.targetRelativePath) != nil })
            }
        }
    }

    private func validationError(for path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return language.text("migration.mapping.error.empty")
        }
        if trimmed.hasPrefix("/") {
            return language.text("migration.mapping.error.absolute")
        }
        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: true)
        if parts.contains("..") || parts.contains(".") {
            return language.text("migration.mapping.error.traversal")
        }
        return nil
    }
}
