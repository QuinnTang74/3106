import Foundation
import Darwin

/// Typed failure surfaced by the grant/retry layer (spec
/// 02-00-ios27-grant-hardening).
///
/// `errorDescription` carries a localization KEY (services return keys so
/// alerts translate per language — same pattern as `FileReplaceError`).
/// The structured payload (code/path/errno) is exposed for UI banners and
/// diagnostics export. Lives in this dependency-free file so the macOS test
/// harness can link it standalone.
enum GrantFailure: Error, LocalizedError, Equatable {
    /// Grant-level denial: the grant primitive itself returned a negative handle.
    case denied(code: Int64, path: String, backend: String)
    /// Write-level denial: grant succeeded but the write got EPERM/EACCES,
    /// including after the automatic re-grant retry.
    case writeDenied(errno: Int32, path: String, grantCode: Int64)

    var errorDescription: String? {
        switch self {
        case .denied(let code, _, _):
            return GrantRetry.failureKey(for: code)
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

/// Permission-error classification and the injectable retry primitive for the
/// iOS 27 grant chain (spec D-05). Dependency-free on purpose: services and
/// the macOS test harness both link this file standalone.
///
/// Why classification lives here: upstream layers translate raw permission
/// errors into semantic ones (FileManagerService folds EPERM into
/// `cannotCopy`; BackupCenter hides errno inside `writeFailed("... errno N")`
/// strings). The retry layer must see through those translations, or the
/// re-grant self-heal never fires exactly when it is needed.
enum GrantRetry {

    // MARK: - Classification (pure functions)

    /// True when `error` is a permission denial in ANY of the shapes the
    /// write paths produce: POSIXError, NSError in the POSIX domain,
    /// CocoaError 513/257, or BackupError.writeFailed with an embedded errno.
    static func isPermissionDenied(_ error: Error) -> Bool {
        errno(of: error) == EPERM || errno(of: error) == EACCES
    }

    /// Best-effort errno extraction from any error shape the write paths
    /// produce. Returns 0 when nothing recognizable is found.
    static func errno(of error: Error) -> Int32 {
        if let posix = error as? POSIXError {
            return Int32(posix.errorCode)
        }
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain {
            return Int32(nsError.code)
        }
        if let cocoa = error as? CocoaError {
            switch cocoa.code {
            case .fileWriteNoPermission, .fileReadNoPermission:
                // Cocoa folds EPERM and EACCES into these two codes.
                return Int32(EACCES)
            default:
                break
            }
        }
        if case .writeFailed(let detail) = error as? BackupError {
            // "open /path errno 1" / "write errno 13" — parse the embedded
            // errno instead of widening BackupError's public surface.
            if let range = detail.range(of: "errno "),
               let value = Int32(detail[range.upperBound...].prefix { $0.isNumber }) {
                return value
            }
        }
        return 0
    }

    // MARK: - Failure-code mapping (pure)

    /// Human-readable semantics for the worse_query failure codes (see
    /// worse_query.m — the C layer already segments by meaning; this maps
    /// them to localization keys). Lives here so GrantFailure and the
    /// diagnostics export share one source of truth without pulling C-linked
    /// dependencies into this file.
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

    // MARK: - Retry primitive (injectable for tests)

    /// grant → body → on a permission denial: invalidate → grant → retry the
    /// body exactly once → surface a structured GrantFailure on the second
    /// failure. A negative grant (broken chain) fails fast with
    /// `denied` before the body runs. Non-permission errors propagate
    /// untouched. All hooks are closures so the macOS test harness can inject
    /// a spy grant/invalidate.
    static func withRetry<T>(
        directory: String,
        backend: String,
        grant: (String) -> Int64,
        invalidate: () -> Void,
        body: () throws -> T
    ) throws -> T {
        let firstGrant = grant(directory)
        guard firstGrant >= 0 else {
            throw GrantFailure.denied(code: firstGrant, path: directory, backend: backend)
        }
        do {
            return try body()
        } catch {
            guard isPermissionDenied(error) else { throw error }
            invalidate()
            let retryGrant = grant(directory)
            guard retryGrant >= 0 else {
                throw GrantFailure.denied(code: retryGrant, path: directory, backend: backend)
            }
            do {
                return try body()
            } catch {
                throw GrantFailure.writeDenied(
                    errno: errno(of: error),
                    path: directory,
                    grantCode: retryGrant
                )
            }
        }
    }
}
