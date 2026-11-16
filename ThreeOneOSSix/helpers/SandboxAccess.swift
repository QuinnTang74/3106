import Foundation

/// The container-access backend selected for the running OS.
///
/// - `kernel`: iOS 17/18 kernel exploit chain (unchanged from 3105).
/// - `badQuery`: the original bad_query grant for iOS 26.0–26.6.1.
/// - `worseQuery`: worse_query sandbox escape for iOS 26.7+ and 27.x.
enum SandboxBackend: String {
    case kernel
    case badQuery
    case worseQuery
    case unsupported

    var displayName: String {
        switch self {
        case .kernel: return "kernel"
        case .badQuery: return "bad_query"
        case .worseQuery: return "worse_query"
        case .unsupported: return "unsupported"
        }
    }
}

/// One place for every sandbox grant. Callers keep treating the return value as
/// an opaque `Int64` handle, so the rest of the app did not need to change.
enum SandboxAccess {
    static var backend: SandboxBackend {
        let v = AppInfo.versionTuple
        if ExploitSupportPolicy.supportsKernelExploit(major: v.major, minor: v.minor, patch: v.patch) {
            return .kernel
        }
        if ExploitSupportPolicy.supportsWorseQuery(major: v.major, minor: v.minor, patch: v.patch) ||
            ExploitSupportPolicy.isExperimental(major: v.major, minor: v.minor) {
            return .worseQuery
        }
        if ExploitSupportPolicy.supportsBadQuery(major: v.major, minor: v.minor, patch: v.patch) {
            return .badQuery
        }
        return .unsupported
    }

    static var appGroup: String? {
        worse_query_app_group()
    }

    static var hasAppGroup: Bool { appGroup != nil }

    static var needsWorseQuery: Bool { backend == .worseQuery }

    /// System Data and System Groups are only reachable through worse_query on
    /// iOS 27; iOS 26 (either backend) and the kernel path keep their old
    /// visibility rules.
    static var systemAreasReachable: Bool {
        switch backend {
        case .kernel, .badQuery:
            return true
        case .worseQuery:
            return AppInfo.versionTuple.major >= 27
        case .unsupported:
            return false
        }
    }

    /// True when the current backend can reach Shared/SystemGroup containers
    /// (MobileGestalt cache, ConfigurationProfiles → Supervised Mode, …).
    /// Only worse_query grants those on iOS 26.7+; the bad_query backend
    /// (iOS 26.0–26.6.1) covers app/daemon/group containers only, and the
    /// kernel backend reaches whatever the kernel permits but historically
    /// the 3105 lineage used it without SystemGroup writes.
    static var systemGroupWritable: Bool {
        // kernel (iOS 17/18) escapes the sandbox entirely and reaches system
        // groups; worse_query grants them on 26.7+/27. Only bad_query
        // (26.0-26.6.1) cannot.
        backend == .worseQuery || backend == .kernel
    }

    /// True when worse_query's App-Group technique is REQUIRED but the
    /// device cannot run it (e.g. iOS 26.0–26.6.1 on bad_query, or a
    /// missing App Group entitlement).
    static var systemGroupFeaturesUnavailable: Bool {
        !systemGroupWritable
    }

    /// System Groups' parent cannot be listed on 27.0.1; callers fall back to
    /// probing known container names.
    static var systemGroupParentListable: Bool {
        let v = AppInfo.versionTuple
        return !(v.major == 27 && v.minor == 0 && v.patch == 1)
    }

    /// Heals an interrupted Caches swap. Called once at launch.
    static func prepare() {
        guard backend == .worseQuery else { return }
        if !worse_query_recover() {
            log("sandbox: worse_query recovery skipped or needs attention")
        }
    }

    /// A lightweight activation probe used by the UI. It verifies the App Group
    /// exists for worse_query, and that the previous grant path is usable for
    /// bad_query.
    static func probe() -> Bool {
        switch backend {
        case .kernel:
            return KernelExploit.hasKernelSandboxAccess()
        case .badQuery:
            let handle = grant(path: ContainerStore.appDataRoot)
            if handle >= 0 {
                release(handle)
                return true
            }
            return false
        case .worseQuery:
            guard let group = appGroup,
                  let groupURL = FileManager.default.containerURL(
                    forSecurityApplicationGroupIdentifier: group
                  ) else {
                log("sandbox: no App Group entitlement — worse_query cannot run")
                return false
            }
            // Exercise the real query path on our own group container first;
            // the parent container root is not grantable on every iOS 26 build.
            // The writable grant runs the T-005 write probe, so a read-only
            // token no longer passes activation (spec D-04).
            if grant(path: groupURL.path, writable: true) >= 0 {
                return true
            }
            let handle = grant(path: ContainerStore.appDataRoot, writable: true)
            if handle >= 0 {
                return true
            }
            log("sandbox: worse_query probe failed on the App Group and app-data root")
            return false
        case .unsupported:
            return false
        }
    }

    // MARK: - Cached probe (T-006)

    private static let probeCacheLock = NSLock()
    private static var probeCache: (value: Bool, at: Date)?
    private static let probeCacheTTL: TimeInterval = 30

    /// `probe()` with a 30-second TTL cache. `hasSandboxAccess()` runs on
    /// every listFiles refresh (ContainerStore), so the real grant chain must
    /// not re-run per refresh. `invalidateWorseQueryCache()` clears this so a
    /// retry never trusts a stale probe result.
    static func probeCached() -> Bool {
        probeCacheLock.lock()
        if let cached = probeCache, Date().timeIntervalSince(cached.at) < probeCacheTTL {
            probeCacheLock.unlock()
            return cached.value
        }
        probeCacheLock.unlock()

        let value = probe()
        probeCacheLock.lock()
        probeCache = (value, Date())
        probeCacheLock.unlock()
        return value
    }

    static func grant(path: String, writable: Bool = false) -> Int64 {
        let clean = path.hasSuffix("/") && path.count > 1 ? String(path.dropLast()) : path
        let handle: Int64
        switch backend {
        case .kernel:
            handle = -1
        case .badQuery:
            var pathC = clean.utf8CString.map { Int8($0) }
            handle = bad_query(&pathC, true, nil, false)
        case .worseQuery:
            var pathC = clean.utf8CString.map { Int8($0) }
            // writable=true routes through grant_ex so a read-only token can
            // no longer fake a successful grant (spec D-03.3/D-04).
            handle = writable ? worse_query_grant_ex(&pathC, 1) : worse_query_grant(&pathC)
        case .unsupported:
            handle = -1
        }
        // Diagnostics-only side effect (spec 02-00-ios27-grant-hardening):
        // the ~20 call sites keep treating the return value as opaque, so
        // failures surface here instead of being swallowed upstream.
        SandboxDiagnostics.record(code: handle, path: clean, backend: backend.displayName)
        return handle
    }

    /// Throwing variant for services that surface grant failures to the user
    /// instead of letting a negative handle cascade into a generic write error.
    static func grantOrThrow(path: String, writable: Bool = false) throws -> Int64 {
        let handle = grant(path: path, writable: writable)
        guard handle >= 0 else {
            throw GrantFailure.denied(
                code: handle,
                path: path,
                backend: backend.displayName
            )
        }
        return handle
    }

    /// Drops every cached worse_query token. Used by the retry path when a
    /// write hits EPERM/EACCES despite a successful grant — a stale token in
    /// the LRU cache is the usual suspect.
    static func invalidateWorseQueryCache() {
        guard backend == .worseQuery else { return }
        worse_query_forget_all()
        probeCacheLock.lock()
        probeCache = nil
        probeCacheLock.unlock()
        log("sandbox: worse_query token cache invalidated")
    }

    /// Grant → body → on EPERM/EACCES drop the token cache, re-grant and
    /// retry the body exactly once (spec D-05). Backend split:
    /// - kernel (iOS 17/18): grants do not exist here (-1 = "not needed"),
    ///   the body runs bare, exactly like the pre-hardening call sites that
    ///   ignored the handle.
    /// - badQuery (26.0–26.6.1): legacy grant-then-run semantics, no retry
    ///   (that backend has its own, already-verified behavior).
    /// - worseQuery (26.7+/27): the full retry chain via GrantRetry.withRetry.
    ///
    /// macOS harness note: on macOS the backend resolves to worseQuery
    /// (Darwin 27) but grants are meaningless — grant returns -1 and the
    /// verify_* harnesses rely on that being non-fatal — so the retry chain
    /// is iOS-only.
    static func withGrant<T>(
        directory: String,
        writable: Bool = false,
        body: () throws -> T
    ) throws -> T {
        switch backend {
        case .kernel:
            return try body()
        case .badQuery:
            _ = grant(path: directory)
            return try body()
        case .worseQuery:
#if os(iOS)
            return try GrantRetry.withRetry(
                directory: directory,
                backend: backend.displayName,
                grant: { grant(path: $0, writable: writable) },
                invalidate: { invalidateWorseQueryCache() },
                body: body
            )
#else
            _ = grant(path: directory, writable: writable)
            return try body()
#endif
        case .unsupported:
            throw GrantFailure.denied(
                code: -1,
                path: directory,
                backend: backend.displayName
            )
        }
    }

    static func release(_ handle: Int64) {
        guard handle >= 0 else { return }
        switch backend {
        case .kernel:
            break
        case .badQuery:
            bad_query_release(handle)
        case .worseQuery:
            worse_query_release(handle)
        case .unsupported:
            break
        }
    }
}