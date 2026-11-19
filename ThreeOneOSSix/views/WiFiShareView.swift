import SwiftUI

/// Wi-Fi transfer screen: address, PIN, on/off switch, live request log.
///
/// The PIN is shown as text rather than masked — it is a one-session LAN code
/// the user has to type into a browser on another machine, and hiding it would
/// make the feature unusable while protecting nothing.
struct WiFiShareView: View {
    @Environment(\.appLanguage) private var language
    @StateObject private var server = WiFiShareServer()

    var body: some View {
        List {
            statusSection
            connectionSection
            requestsSection
            usageSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(language.text("wifishare.title"))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            // Leaving the screen stops the server: a listener the user can no
            // longer see is a listener they cannot reason about.
            server.stop()
        }
    }

    private var statusSection: some View {
        Section {
            Toggle(language.text("wifishare.enable"), isOn: Binding(
                get: { server.isRunning },
                set: { enabled in
                    if enabled { server.start() } else { server.stop() }
                }
            ))
            switch server.state {
            case .stopped:
                Text(language.text("wifishare.stopped"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .starting:
                HStack(spacing: 8) {
                    ProgressView()
                    Text(language.text("wifishare.starting"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            case .running(let port, let address):
                LabeledContent(language.text("wifishare.address")) {
                    Text("http://\(address):\(port)")
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }
                LabeledContent(language.text("wifishare.connections")) {
                    Text("\(server.activeConnections)")
                        .font(.footnote.monospaced())
                }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } header: {
            Label(language.text("wifishare.title"), systemImage: "wifi")
        } footer: {
            Text(language.text("wifishare.footer"))
        }
    }

    @ViewBuilder
    private var connectionSection: some View {
        Section {
            LabeledContent(language.text("wifishare.user")) {
                Text(WiFiSharePolicy.username)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
            }
            LabeledContent(language.text("wifishare.pin")) {
                Text(server.pin.isEmpty ? "——————" : server.pin)
                    .font(.title3.monospaced())
                    .textSelection(.enabled)
            }
            LabeledContent(language.text("wifishare.folder")) {
                Text(server.rootURL.lastPathComponent)
                    .font(.footnote.monospaced())
            }
        } header: {
            Label(language.text("wifishare.credentials"), systemImage: "key")
        } footer: {
            Text(language.text("wifishare.pin_footer"))
        }
    }

    @ViewBuilder
    private var requestsSection: some View {
        if !server.recentRequests.isEmpty {
            Section(language.text("wifishare.requests")) {
                ForEach(Array(server.recentRequests.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    private var usageSection: some View {
        Section {
            Text(language.text("wifishare.usage_curl"))
                .font(.caption.monospaced())
                .textSelection(.enabled)
        } header: {
            Label(language.text("wifishare.usage"), systemImage: "terminal")
        } footer: {
            Text(language.text("wifishare.usage_footer"))
        }
    }
}