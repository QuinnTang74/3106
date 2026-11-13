import SwiftUI

/// Lock-screen footnote editor: current value display, single-line text
/// field with the 256-character cap, apply/clear through the shared risk
/// confirmation. Card sits in the device section of the feature hub, right
/// after Supervised Mode (same SystemGroup family, same verified pipeline).
struct SystemSettingsView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss

    @State private var currentFootnote: String?
    @State private var draft = ""
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var riskAction: RiskAction?
    @State private var resultMessage: String?
    @State private var errorMessage: String?

    enum RiskAction: Identifiable {
        case apply
        case clear
        var id: String { "\(self)" }
    }

    var body: some View {
        List {
            if loadFailed {
                Section {
                    Label(language.text("systemsettings.error.unavailable"), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            } else {
                currentSection
                editSection
            }
            if let message = resultMessage {
                Section {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                }
            }
        }
        .navigationTitle(language.text("systemsettings.title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .sheet(item: $riskAction) { action in
            RiskConfirmationView(
                titleKey: "systemsettings.title",
                riskKey: "risk.systemSettings",
                confirmActionKey: "risk.systemSettings.confirm_action",
                onCancel: nil,
                onConfirm: {
                    commit(action)
                }
            )
        }
        .alert(language.text("systemsettings.error.title"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil }
        })) {
            Button(language.text("common.ok"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var currentSection: some View {
        Section {
            if isLoading {
                HStack { ProgressView().controlSize(.small) }
            } else if let footnote = currentFootnote, !footnote.isEmpty {
                Text(footnote)
                    .font(.subheadline)
                    .textSelection(.enabled)
            } else {
                Text(language.text("systemsettings.current_empty"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(language.text("systemsettings.section.current"))
        }
    }

    @ViewBuilder
    private var editSection: some View {
        Section {
            TextField(language.text("systemsettings.field_placeholder"),
                      text: $draft, prompt: nil)
                .lineLimit(1)
                .autocorrectionDisabled()
            HStack {
                Spacer()
                Text("\(draft.count) / \(SystemSettingsService.maxFootnoteLength)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(draft.count > SystemSettingsService.maxFootnoteLength ? .red : .secondary)
            }
            Button(language.text("systemsettings.apply")) {
                riskAction = .apply
            }
            .fontWeight(.semibold)
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            Button(role: .destructive) {
                riskAction = .clear
            } label: {
                Label(language.text("systemsettings.clear"), systemImage: "eraser")
            }
            .disabled(currentFootnote == nil || (currentFootnote?.isEmpty ?? true))
        } header: {
            Text(language.text("systemsettings.section.edit"))
        } footer: {
            Text(language.text("systemsettings.edit_footer"))
        }
    }

    private func load() {
        isLoading = true
        loadFailed = false
        DispatchQueue.global(qos: .userInitiated).async {
            let loaded = try? SystemSettingsService.currentFootnote()
            DispatchQueue.main.async {
                currentFootnote = loaded
                if loaded == nil && currentFootnote == nil {
                    loadFailed = false // nil is the factory state, not failure
                }
                isLoading = false
            }
        }
    }

    private func commit(_ action: RiskAction) {
        let payload: String? = (action == .apply) ? draft : nil
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try SystemSettingsService.apply(payload)
                let refreshed = try? SystemSettingsService.currentFootnote()
                DispatchQueue.main.async {
                    currentFootnote = refreshed
                    resultMessage = action == .apply
                        ? language.text("systemsettings.applied")
                        : language.text("systemsettings.cleared")
                }
            } catch {
                DispatchQueue.main.async {
                    errorMessage = localized(error)
                }
            }
        }
    }

    private func localized(_ error: Error) -> String {
        if let local = error as? LocalizedError, let key = local.errorDescription {
            let translated = language.text(key)
            return translated == key ? String(describing: error) : translated
        }
        return String(describing: error)
    }
}
