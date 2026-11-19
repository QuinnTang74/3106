import SwiftUI
import UIKit

@main
struct ThreeOneOSSixApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var patchDraftCoordinator = PatchDraftCoordinator()
    @StateObject private var fileOperationCoordinator = FileOperationCoordinator()
    @StateObject private var patchStore = PatchProjectStore()
    @StateObject private var repositoryStore = PackageRepositoryStore()
    @StateObject private var migrationTaskCenter = MigrationTaskCenter()
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.english.rawValue
    @State private var showOnboarding = OnboardingStore.shouldShow()
    @State private var showAttribution = false
    @State private var updateOffer: AppUpdateChecker.Offer?
    @State private var configImportError: String?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init() {
        // Seed the UI language before the first view body runs. `@AppStorage`
        // reads UserDefaults on every access, so a write here is visible to
        // the first render. A stored value always wins — see seedIfNeeded.
        LanguageResolver.seedIfNeeded()
        setupLogCapture()
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let appBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let cpu = DeviceCPU.cpuFamily.map { String(format: "0x%X", $0) } ?? "unknown"
        log("app: 3106 \(appVersion) (\(appBuild)) launching — iOS \(AppInfo.osVersion) (\(AppInfo.osBuild)) \(AppInfo.machineName) cpu=\(cpu)")
        SandboxAccess.prepare()
        TempSpaceRegistry.purgeExpired()
    }

    private var language: AppLanguage {
        AppLanguage(rawValue: languageCode) ?? .english
    }

    private func importConfigPackage(at url: URL) {
        do {
            _ = try MigrationConfigBackupService.importPackage(at: url)
            migrationTaskCenter.refreshStoredSets()
            configImportError = nil
            log("migration: config package imported — \(url.lastPathComponent)")
        } catch {
            log("migration: config package import failed — \(error)")
            configImportError = language.errorText(error)
        }
    }

    /// GestaltX #133: a share extension may drop packages into the App Group
    /// inbox without delivering an onOpenURL callback. Read whichever App
    /// Group the side-loaded build was actually signed with.
    private func importSharedConfigPackages() {
        guard let group = SandboxAccess.appGroup,
              let inbox = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: group)?
                .appendingPathComponent("SharedConfigInbox", isDirectory: true) else { return }
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: inbox,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        for url in urls where url.pathExtension.lowercased()
            == MigrationConfigBackupService.packageExtension {
            importConfigPackage(at: url)
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func checkForUpdate() {
        Task {
            guard let offer = await AppUpdateChecker.check() else { return }
            await MainActor.run { updateOffer = offer }
        }
    }

    /// Foreground-switch variant: 30-minute throttle lives in the checker
    /// (persisted), so repeated quick app switches cost nothing.
    private func checkForUpdateThrottled() {
        Task {
            guard let offer = await AppUpdateChecker.throttledForegroundCheck() else { return }
            await MainActor.run { updateOffer = offer }
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environmentObject(appState)
                    .environmentObject(patchDraftCoordinator)
                    .environmentObject(fileOperationCoordinator)
                    .environmentObject(patchStore)
                    .environmentObject(repositoryStore)
                    .environmentObject(migrationTaskCenter)
                    .environment(\.appLanguage, language)
                    .environment(\.locale, language.locale)
                    .opacity(showOnboarding ? 0 : 1)
                    .allowsHitTesting(!showOnboarding)

                if showOnboarding {
                    OnboardingView {
                        OnboardingStore.markCompleted()
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) {
                            showOnboarding = false
                        }
                        appState.detectSupport()
                        checkForUpdate()
                    }
                    .environment(\.appLanguage, language)
                    .environment(\.locale, language.locale)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .scale(scale: 0.98))
                    )
                    .zIndex(1)
                }
            }
            .displayIdentityAttribution(isPresented: $showAttribution, enabled: !showOnboarding)
            .sheet(isPresented: $showAttribution) {
                DisplayAttributionSheet()
            }
            .alert(
                language.text("config.import_error.title"),
                isPresented: .init(
                    get: { configImportError != nil },
                    set: { if !$0 { configImportError = nil } }
                )
            ) {
                Button(language.text("common.ok"), role: .cancel) {
                    configImportError = nil
                }
            } message: {
                Text(configImportError ?? "")
            }
            .alert(item: $updateOffer) { offer in
                Alert(
                    title: Text(language.text("update.title")),
                    message: Text(language.text("update.message", offer.version) + "\n" + language.text("update.current", AppInfo.appVersion)),
                    primaryButton: .default(Text(language.text("update.agree"))) {
                        UIApplication.shared.open(offer.url)
                    },
                    secondaryButton: .cancel(Text(language.text("common.cancel"))) {}
                )
            }
            .onAppear {
                if !showOnboarding {
                    appState.detectSupport()
                    checkForUpdate()
                }
                migrationTaskCenter.refreshPendingResumes()
                importSharedConfigPackages()
            }
            .onChange(of: scenePhase) { phase in
                guard phase == .active, !showOnboarding else { return }
                appState.detectSupport()
                // 3.2.4: also probe for updates on foreground switches —
                // the cold-start check alone misses releases published
                // while the app idles in the background. Throttled to one
                // probe per 30 minutes; failures stay silent here.
                checkForUpdateThrottled()
            }
            .onOpenURL { url in
                // Config backup packages (.3106cfg) route to the migration
                // importer; everything else stays on the patch-package path.
                if url.isFileURL,
                   url.pathExtension.lowercased() == MigrationConfigBackupService.packageExtension {
                    importConfigPackage(at: url)
                    return
                }
                patchDraftCoordinator.presentImport(url)
            }
        }
    }
}

class AppState: ObservableObject {
    @Published var exploitStatus: ExploitStatus = .notStarted
    @Published var unsupportedMessage: String?

    /// Same storage key as the `@AppStorage` in `ThreeOneOSSixApp`. AppState
    /// is a plain class, so it cannot read the struct's property directly —
    /// it resolves the language from the shared defaults instead.
    private var language: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: AppLanguage.storageKey) ?? "")
            ?? .english
    }
    @Published var kernelExploitRunning = false

    var kernelExploitApplicable: Bool {
        KernelExploit.isApplicable(
            major: AppInfo.versionTuple.major,
            minor: AppInfo.versionTuple.minor,
            patch: AppInfo.versionTuple.patch,
            build: AppInfo.osBuild,
            isA10: DeviceCPU.isA10
        )
    }

    var isSupported: Bool { unsupportedMessage == nil }

    func detectSupport() {
        let v = AppInfo.versionTuple
        let supported = ExploitSupportPolicy.isSupported(
            major: v.major,
            minor: v.minor,
            patch: v.patch,
            build: AppInfo.osBuild,
            isA10: DeviceCPU.isA10
        )
#if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--simulate-access") {
            exploitStatus = .success(method: "Simulator preview")
        }
#endif

        if !supported {
            // The explanation lives in RejectionReason so onboarding can show
            // the identical copy without a second hand-maintained copy drifting
            // the moment a version boundary moves.
            if let reason = RejectionReason.make(
                major: v.major,
                minor: v.minor,
                patch: v.patch,
                build: AppInfo.osBuild,
                osVersion: "iOS \(AppInfo.osVersion) (\(AppInfo.osBuild))",
                isA10: DeviceCPU.isA10
            ) {
                unsupportedMessage = language.text(reason.key, reason.arguments)
            }
        }
        if let unsupportedMessage {
            exploitStatus = .unsupported(unsupportedMessage)
            return
        }

        let applicable = KernelExploit.isApplicable(
            major: v.major,
            minor: v.minor,
            patch: v.patch,
            build: AppInfo.osBuild,
            isA10: DeviceCPU.isA10
        )
        guard applicable else { return }

        refreshKernelExploitStatus()
        // Deliberately no auto-run. The kernel chain reboots the device when it
        // goes wrong, and a process that quietly executes an exploit at launch
        // gives the user no chance to consent or to read what happened. The
        // Unlock screen is the only entry point now; `kernelExploitRunning`,
        // `exploitStatus` and the banner state drive it.
    }

    /// True when the app should offer the Unlock screen: a kernel backend that
    /// has not succeeded yet. Deliberately excludes a settled failure — retrying
    /// automatically after a failure would recreate the silent loop this change
    /// removed. The user re-opens Unlock explicitly to try again.
    var needsUnlock: Bool {
        ExploitSupportPolicy.requiresExplicitUnlock(
            isKernelBackend: SandboxAccess.backend == .kernel,
            hasAccess: exploitStatus.isSuccess
        )
    }

    private func refreshKernelExploitStatus() {
        guard !kernelExploitRunning else { return }

        // iOS < 26: kernel R/W success persists (no sandbox probe)
        // iOS >= 26: verify full sandbox escape is still active
        if KernelExploit.requiresSandboxEscape {
            if KernelExploit.hasSandboxAccess() {
                if !exploitStatus.isSuccess {
                    exploitStatus = .success(method: SandboxAccess.backend.displayName)
                    log("app: existing \(SandboxAccess.backend.displayName) access is still active")
                }
            } else if exploitStatus.isSuccess {
                exploitStatus = .notStarted
                log("app: sandbox access is no longer active")
            }
        }
    }

    func runKernelExploitIfNeeded() {
        refreshKernelExploitStatus()
        guard !kernelExploitRunning,
              !exploitStatus.isSuccess,
              !exploitStatus.isFailed else { return }
        kernelExploitRunning = true
        exploitStatus = .notStarted
        let backend = SandboxAccess.backend
        log("app: running \(backend.displayName) access setup on background...")
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = KernelExploit.run()
            DispatchQueue.main.async {
                self.kernelExploitRunning = false
                if ok {
                    self.exploitStatus = .success(method: backend.displayName)
                    if backend == .kernel {
                        log("app: kernel access active")
                    } else {
                        log("app: \(backend.displayName) access active")
                    }
                } else {
                    self.exploitStatus = .failed(method: backend.displayName, code: -1)
                    if backend == .worseQuery && !SandboxAccess.hasAppGroup {
                        log("app: worse_query needs an App Group; re-sign with a tool that provides one")
                    } else {
                        log("app: \(backend.displayName) setup failed — relaunch the app before retrying")
                    }
                }
            }
        }
    }
}
