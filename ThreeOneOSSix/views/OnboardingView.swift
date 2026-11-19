import SwiftUI

/// Single-page first-launch screen.
///
/// Replaces the previous four-step wizard (language → welcome → versions →
/// install). Three of those steps contradicted how onboarding should behave:
///
/// - the language step asked for a choice the system already knows, so it is
///   gone — the language is seeded from `Locale.preferredLanguages` at launch
///   and the only switch lives in Settings;
/// - the welcome step carried no information the versions step did not;
/// - "is this version supported" and "which versions are supported" are one
///   question, so they share one screen.
///
/// What remains is the state the user actually needs before touching the app:
/// whether their device works, what the supported matrix is, and — only on the
/// backends that need it — the signing requirement.
struct OnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appLanguage) private var language
    var onComplete: () -> Void

    private var versions: (major: Int, minor: Int, patch: Int) { AppInfo.versionTuple }

    private var supported: Bool {
        ExploitSupportPolicy.isSupported(
            major: versions.major,
            minor: versions.minor,
            patch: versions.patch,
            build: AppInfo.osBuild,
            isA10: DeviceCPU.isA10
        )
    }

    private var rejection: RejectionReason.Reason? {
        RejectionReason.make(
            major: versions.major,
            minor: versions.minor,
            patch: versions.patch,
            build: AppInfo.osBuild,
            osVersion: "iOS \(AppInfo.osVersion) (\(AppInfo.osBuild))",
            isA10: DeviceCPU.isA10
        )
    }

    /// The App Group requirement only applies where worse_query is the backend.
    /// Older devices work without it, so showing the paragraph there would be
    /// a warning about a constraint that does not exist for them.
    private var showsSigningRequirement: Bool { SandboxAccess.needsWorseQuery }

    var body: some View {
        ZStack {
            AppTheme.pageBackground
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 24) {
                    header
                    statusBadge
                    if let rejection {
                        rejectionNotice(rejection)
                    }
                    versionMatrix
                    if showsSigningRequirement {
                        signingRequirement
                    }
                }
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 32)
                .padding(.bottom, 28)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            controls
        }
        .tint(AppTheme.accent)
    }

    private var header: some View {
        VStack(spacing: 12) {
            AppLogo(size: 72)
            Text(language.text("onboarding.versions_title"))
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(language.text("onboarding.versions_subtitle"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 10) {
            Image(systemName: supported ? "checkmark.seal.fill" : "xmark.octagon.fill")
                .foregroundStyle(supported ? Color.green : Color.red)
                .font(.title3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(language.text(supported ? "onboarding.support_ok" : "onboarding.support_no"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("iOS \(AppInfo.osVersion) (\(AppInfo.osBuild))")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            (supported ? Color.green : Color.red).opacity(0.10),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    private func rejectionNotice(_ reason: RejectionReason.Reason) -> some View {
        Text(language.text(reason.key, arguments: reason.arguments))
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                Color(uiColor: .secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
    }

    private var versionMatrix: some View {
        VStack(alignment: .leading, spacing: 10) {
            versionRow(
                icon: "checkmark.circle.fill",
                title: "iOS 17",
                value: ExploitSupportPolicy.verifiedIOS17Range,
                color: .green
            )
            versionRow(
                icon: "checkmark.circle.fill",
                title: "iOS 18",
                value: ExploitSupportPolicy.verifiedIOS18Range,
                color: .green
            )
            versionRow(
                icon: "checkmark.circle.fill",
                title: "iOS 26",
                value: "\(ExploitSupportPolicy.verifiedIOS26BadQueryRange) · \(ExploitSupportPolicy.verifiedIOS26WorseQueryRange)",
                color: .green
            )
            versionRow(
                icon: "checkmark.circle.fill",
                title: "iOS 27",
                value: ExploitSupportPolicy.verifiedIOS27Range,
                color: .green
            )
            // 27.3 stays a separate row because its boundary is a build number,
            // not a version number. Folding it into the row above would read as
            // "all of 27.3 is supported", which is exactly the belief that got
            // 27.3 beta 2+ users a green badge and failing writes.
            versionRow(
                icon: "checkmark.circle.fill",
                title: "iOS 27.3",
                value: "\(ExploitSupportPolicy.verifiedIOS27BuildGatedRange) · \(ExploitSupportPolicy.verifiedIOS27Builds.joined(separator: ", "))",
                color: .green
            )
        }
    }

    private var signingRequirement: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(language.text("onboarding.app_group_note"), systemImage: "signature")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(language.text("onboarding.install_message"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(language.text("onboarding.install_footer"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Button {
                onComplete()
            } label: {
                HStack(spacing: 6) {
                    Text(language.text("common.next"))
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func versionRow(icon: String, title: String, value: String, color: Color) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                Image(systemName: icon).foregroundStyle(color)
                Text(title).fontWeight(.semibold)
                Spacer()
                Text(value)
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                    Text(title)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
                Text(value)
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.leading, 26)
            }
        }
        .font(.subheadline)
        .padding(12)
        .background(
            Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }
}