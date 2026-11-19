import SwiftUI

/// Top-of-screen prompt shown while a kernel-backed device is still locked.
///
/// Cheap to render and impossible to miss: the kernel chain is the only way to
/// get container access on iOS 17/18, so if it has not run, every file feature
/// below is inert. Making that state visible is the whole point of moving the
/// chain out of launch.
struct UnlockBanner: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: appState.kernelExploitRunning ? "hourglass" : "lock.open")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 1) {
                Text(language.text("unlock.banner_title"))
                    .font(.footnote.weight(.semibold))
                Text(appState.kernelExploitRunning
                     ? language.text("unlock.running")
                     : language.text("unlock.banner_detail"))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 4)
            if !appState.kernelExploitRunning {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.accent)
                // A shadow keeps the banner readable over both light lists and
                // dark backgrounds without adding a material layer.
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(language.text("unlock.banner_title"))
    }
}