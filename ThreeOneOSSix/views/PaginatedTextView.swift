import SwiftUI
import UniformTypeIdentifiers

/// Shared long-text reader: fixed-character pagination, full-text copy
/// (pasteboard marked local-only so long logs never sync to the Universal
/// Clipboard), and plain-text ShareLink. Used by the log viewer and by
/// migration diagnostic reports.
struct PaginatedTextView: View {
    let text: String
    var titleKey: String = "diagnostics.title"

    @State private var page = 0
    @State private var copied = false
    @Environment(\.appLanguage) private var language

    static let charactersPerPage = TextPagination.charactersPerPage

    private var pages: [String] { TextPagination.paginate(text) }

    var body: some View {
        let pages = pages
        VStack(spacing: 0) {
            if pages.isEmpty {
                Text(language.text("diagnostics.empty"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // UITextView via representable: one unbounded SwiftUI Text
                // leaves a tall blank layout gap on device for very long
                // strings; a scrollable text view does not.
                ScrollView {
                    Text(pages[page])
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AppTheme.pageInset)
                }
                .background(AppTheme.consoleBackground)

                Divider()
                HStack(spacing: 14) {
                    Button {
                        if page > 0 { page -= 1 }
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(page == 0)

                    Text(language.text("diagnostics.page_of", page + 1, pages.count))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Button {
                        if page < pages.count - 1 { page += 1 }
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(page >= pages.count - 1)

                    Spacer()

                    Button {
                        UIPasteboard.general.setItems(
                            [[UTType.utf8PlainText.identifier: text]],
                            options: [.localOnly: true]
                        )
                        copied = true
                        SoundEffects.play(.success)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                            copied = false
                        }
                    } label: {
                        Label(copied ? language.text("diagnostics.copied") : language.text("diagnostics.copy"),
                              systemImage: copied ? "checkmark" : "doc.on.doc")
                    }

                    ShareLink(item: text) {
                        Label(language.text("diagnostics.share"), systemImage: "square.and.arrow.up")
                    }
                }
                .font(.subheadline)
                .padding(.horizontal, AppTheme.pageInset)
                .padding(.vertical, 10)
            }
        }
        .navigationTitle(language.text(titleKey))
        .navigationBarTitleDisplayMode(.inline)
    }
}
