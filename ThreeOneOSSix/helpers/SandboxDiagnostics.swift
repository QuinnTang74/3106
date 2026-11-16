import Foundation
import Darwin

/// Diagnostic layer for the sandbox grant chain (iOS 27 hardening, spec
/// 02-00-ios27-grant-hardening).
///
/// `SandboxAccess.grant` records every result here — the ~20 call sites keep
/// treating the return value as an opaque handle, so nothing else had to
/// change. When writes fail on iOS 27 the failure is no longer silent: the
/// UI banner and the settings-page diagnostics view read the last grant code
/// and the recent-record ring, and `exportText()` produces a paste-ready
/// report for remote attribution (spec decision: diagnostics before fixes).
enum SandboxDiagnostics {

    struct GrantRecord: Identifiable, Equatable {
        let id = UUID()
        let code: Int64
        let path: String
        let backend: String
        let at: Date
    }

    private static let lock = NSLock()
    private static let ringLimit = 50
    private static var ring: [GrantRecord] = []
    private static var last: GrantRecord?

    // MARK: - Recording

    /// Records one grant result. Called from `SandboxAccess.grant` before it
    /// returns; never changes the grant's return-value semantics.
    static func record(code: Int64, path: String, backend: String) {
        lock.lock()
        defer { lock.unlock() }
        let entry = GrantRecord(code: code, path: path, backend: backend, at: Date())
        last = entry
        ring.append(entry)
        if ring.count > ringLimit {
            ring.removeFirst(ring.count - ringLimit)
        }
    }

    /// The most recent grant result, or nil when no grant has run yet.
    static var lastGrant: GrantRecord? {
        lock.lock()
        defer { lock.unlock() }
        return last
    }

    /// A snapshot of the most recent records, oldest first.
    static var recentGrants: [GrantRecord] {
        lock.lock()
        defer { lock.unlock() }
        return ring
    }

    /// Forgets all recorded grants (used by tests and the diagnostics view's
    /// clear action).
    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        ring.removeAll()
        last = nil
    }

    // MARK: - Failure mapping

    /// Human-readable semantics for the worse_query failure codes (see
    /// worse_query.m — the C layer already segments by meaning; this maps
    /// them to localization keys).
    static func failureKey(for code: Int64) -> String {
        switch code {
        case -1: return "sandbox.error.no_app_group"
        case -2, -3: return "sandbox.error.query_api"
        case -4: return "sandbox.error.swap_failed"
        case -5, -6, -7: return "sandbox.error.token"
        case -8: return "sandbox.error.token_unopenable"
        case -9: return "sandbox.error.token_read_only"
        case -254: return "sandbox.error.lstat_denied"
        default: return "sandbox.error.unknown"
        }
    }

    // MARK: - Export

    /// Which flags candidate the C layer learned for this OS major, surfaced
    /// for remote attribution (the preference key is versioned per design
    /// D-03.2; before T-004 lands, the legacy key is what exists).
    private static var flagsPreferenceSummary: String {
        let defaults = UserDefaults.standard
        if let versioned = defaults.object(forKey: "wq.preferredQueryFlags.v\(AppInfo.versionTuple.major)") as? Int {
            return "v\(AppInfo.versionTuple.major)=candidate \(versioned)"
        }
        if let legacy = defaults.object(forKey: "wq.preferredQueryFlags") as? Int {
            return "legacy=\(legacy == 1 ? "alt" : "standard")"
        }
        return "not learned"
    }

    /// Paste-ready diagnostic report (modeled after LogView.shareText).
    /// Includes OS/build, machine, app version, backend, App Group, probe
    /// result, LS layout hit, and the recent grant ring.
    static func exportText(probeResult: Bool? = nil, lsLayoutHit: String? = nil) -> String {
        var lines: [String] = []
        lines.append("3106 Sandbox Diagnostics")
        lines.append("iOS \(AppInfo.osVersion) (\(AppInfo.osBuild)) — \(AppInfo.machineName)")
        lines.append("App: \(AppInfo.appVersion) — Generated: \(Date())")
        lines.append("Backend: \(SandboxAccess.backend.displayName)")
        lines.append("App Group: \(SandboxAccess.appGroup ?? "(none)")")
        if let probeResult {
            lines.append("Probe: \(probeResult ? "ok" : "FAILED")")
        } else {
            lines.append("Probe: not run")
        }
        if let lsLayoutHit {
            lines.append("LS layout hit: \(lsLayoutHit)")
        }
        lines.append("Flags preference: \(Self.flagsPreferenceSummary)")
        lines.append("")
        lines.append("Recent grants (oldest first, max \(ringLimit)):")
        let snapshot = recentGrants
        if snapshot.isEmpty {
            lines.append("  (none recorded)")
        } else {
            let df = DateFormatter()
            df.dateFormat = "HH:mm:ss"
            for entry in snapshot {
                let verdict = entry.code >= 0 ? "ok" : "FAIL(\(entry.code) = \(failureKey(for: entry.code)))"
                lines.append("  [\(df.string(from: entry.at))] \(entry.backend) \(verdict) path=\(entry.path)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

/// The typed error thrown by `SandboxAccess.grantOrThrow` / `withGrant`.
///
/// `errorDescription` carries a localization KEY (services return keys so
/// alerts translate per language — same pattern as `FileReplaceError`).
/// The structured payload (code/path/errno) is exposed for UI banners and
/// diagnostics export.
enum GrantFailure: Error, LocalizedError {
    /// Grant-level denial: the grant primitive itself returned a negative handle.
    case denied(code: Int64, path: String, backend: String)
    /// Write-level denial: grant succeeded but the write got EPERM/EACCES.
    case writeDenied(errno: Int32, path: String, grantCode: Int64)

    var errorDescription: String? {
        switch self {
        case .denied(let code, _, _):
            return SandboxDiagnostics.failureKey(for: code)
        case .writeDenied(let errno, _, _):
            return errno == Int32(EROFS) ? "sandbox.error.write_denied_ro" : "sandbox.error.write_denied"
        }
    }

    /// Compact payload for banners/log lines, e.g. "grant=-8 path=/var/...".
    var diagnosticSummary: String {
        switch self {
        case .denied(let code, let path, let backend):
            return "grant=\(code) backend=\(backend) path=\(path)"
        case .writeDenied(let errno, let path, let grantCode):
            return "errno=\(errno) grant=\(grantCode) path=\(path)"
        }
    }
}
