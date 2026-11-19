import SwiftUI

/// Supervised Mode page (Regitela parity): shows the current state, flips
/// it behind the full-screen risk confirmation. The MDM warning is explicit
/// because flipping supervision on an MDM-managed device breaks the
/// management relationship.
struct SupervisedModeView: View {
    @Environment(\.appLanguage) private var language
    @State private var isSupervised: Bool?
    @State private var audit: SupervisedModeService.CloudConfigAudit = .clean
    @State private var isBusy = false
    @State private var showConfirmation = false
    @State private var showClearConfirmation = false
    @State private var pendingValue = false
    @State private var activeAlert: SupervisedAlert?
    @State private var hasLoaded = false

    var body: some View {
        List {
            BackendNoticeBanner(unavailableKey: "backend.notice.supervised")
            Section {
                LabeledContent(language.text("supervised.state")) {
                    Text(stateText)
                        .foregroundStyle(isSupervised == true ? AppTheme.accent : .secondary)
                        .font(.headline.monospacedDigit())
                }
            } header: {
                Label(language.text("supervised.header"), systemImage: "checkmark.shield")
            } footer: {
                Text(SupervisedModeService.plistPath)
                    .font(.caption2.monospaced())
            }

            Section {
                Button {
                    pendingValue = true
                    showConfirmation = true
                } label: {
                    Label(language.text("supervised.enable"), systemImage: "shield.lefthalf.filled")
                }
                .disabled(isBusy || isSupervised == true)

                Button(role: .destructive) {
                    pendingValue = false
                    showConfirmation = true
                } label: {
                    Label(language.text("supervised.disable"), systemImage: "shield.slash")
                }
                .disabled(isBusy || isSupervised == false)

                Button {
                    reload()
                } label: {
                    Label(language.text("supervised.refresh"), systemImage: "arrow.clockwise")
                }
                .disabled(isBusy)
            } footer: {
                Text(language.text("supervised.warning"))
            }

            auditSection

            if let errorNote {
                Section {
                    Text(errorNote)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle(language.text("supervised.title"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { reload() }
        .onAppear {
            guard !hasLoaded else { return }
            hasLoaded = true
            reload()
        }
        .sheet(isPresented: $showConfirmation) {
            RiskConfirmationView(
                titleKey: pendingValue ? "supervised.enable" : "supervised.disable",
                riskKey: "risk.supervised",
                confirmActionKey: "common.confirm"
            ) {
                apply(pendingValue)
            }
        }
        .alert(language.text("supervised.audit.clear"), isPresented: $showClearConfirmation) {
            Button(language.text("supervised.audit.clear"), role: .destructive) {
                clearFakeSupervision()
            }
            Button(language.text("common.cancel"), role: .cancel) {}
        } message: {
            Text(language.text("supervised.audit.clear_confirm"))
        }
        .alert(item: $activeAlert, content: alertContent)
    }

    @ViewBuilder
    private var auditSection: some View {
        Section {
            Label {
                Text(auditText)
                    .font(.subheadline)
            } icon: {
                Image(systemName: auditIcon)
                    .foregroundStyle(auditColor)
            }
            if case .fakeResidue = audit {
                Button(role: .destructive) {
                    showClearConfirmation = true
                } label: {
                    Label(language.text("supervised.audit.clear"), systemImage: "trash")
                }
                .disabled(isBusy)
            }
        } header: {
            Label(language.text("supervised.audit.header"), systemImage: "stethoscope")
        } footer: {
            Text(language.text("supervised.audit.footer"))
        }
    }

    private var auditText: String {
        switch audit {
        case .clean:
            return language.text("supervised.audit.clean")
        case .genuineMDM(let org):
            return language.text("supervised.audit.genuine", org)
        case .fakeResidue(let org):
            return language.text("supervised.audit.fake", org)
        }
    }

    private var auditIcon: String {
        switch audit {
        case .clean: return "checkmark.shield"
        case .genuineMDM: return "building.2.crop.circle"
        case .fakeResidue: return "exclamationmark.triangle.fill"
        }
    }

    private var auditColor: Color {
        switch audit {
        case .clean: return .green
        case .genuineMDM: return .secondary
        case .fakeResidue: return .red
        }
    }

    private var stateText: String {
        switch isSupervised {
        case .some(true): return language.text("supervised.on")
        case .some(false): return language.text("supervised.off")
        case .none: return language.text("supervised.unknown")
        }
    }

    private var errorNote: String? {
        nil // reserved: surfaced through alerts for now
    }

    private func reload() {
        isBusy = true
        DispatchQueue.global(qos: .utility).async {
            let state = SupervisedModeService.currentState()
            let audit = SupervisedModeService.audit()
            DispatchQueue.main.async {
                isSupervised = state
                self.audit = audit
                isBusy = false
            }
        }
    }

    private func clearFakeSupervision() {
        isBusy = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try SupervisedModeService.clearFakeSupervision()
                let state = SupervisedModeService.currentState()
                let audit = SupervisedModeService.audit()
                DispatchQueue.main.async {
                    isSupervised = state
                    self.audit = audit
                    isBusy = false
                    SoundEffects.play(.success)
                    activeAlert = .message(language.text("supervised.audit.cleared"))
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

    private func apply(_ value: Bool) {
        isBusy = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try SupervisedModeService.apply(value)
                DispatchQueue.main.async {
                    isSupervised = SupervisedModeService.currentState()
                    isBusy = false
                    SoundEffects.play(.success)
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

    private func alertContent(for alert: SupervisedAlert) -> Alert {
        Alert(
            title: Text(language.text("supervised.title")),
            message: Text(alert.message),
            dismissButton: .default(Text(language.text("common.ok")))
        )
    }
}

enum SupervisedAlert: Identifiable {
    case message(String)

    var message: String {
        if case .message(let text) = self { return text }
        return ""
    }

    var id: String { "supervised-\(message)" }
}
