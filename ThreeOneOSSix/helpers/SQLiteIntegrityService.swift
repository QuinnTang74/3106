import Foundation
import Darwin

/// Read-only SQLite integrity checking (WCMigrate's DatabaseInspector design;
/// independent implementation). Opens the target database with
/// SQLITE_OPEN_READONLY and runs `PRAGMA quick_check` with a bounded row
/// budget so a corrupt/bloated database cannot pin the main thread.
///
/// Self-contained dlopen bridge — the SQLiteViewerView has its own fuller
/// bridge; the two are independent by design (each service owns its symbols,
/// matching the project's per-service dependency habit).
enum SQLiteIntegrityService {

    enum IntegrityError: Error, Equatable {
        case bridgeUnavailable
        case openFailed(String)
        case queryFailed(String)
    }

    struct Report: Equatable {
        /// "ok" when quick_check found nothing; otherwise the first problems.
        var status: String
        var problemCount: Int
        var isHealthy: Bool { status == "ok" }
    }

    /// Row budget for quick_check output; quick_check reports one row per
    /// problem, so a corrupt database still terminates promptly.
    static let maxRows = 64

    private final class Bridge {
        typealias OpenFn = @convention(c) (UnsafePointer<CChar>?, UnsafeMutablePointer<OpaquePointer?>?, Int32, UnsafePointer<CChar>?) -> Int32
        typealias CloseFn = @convention(c) (OpaquePointer?) -> Int32
        typealias PrepareFn = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, Int32, UnsafeMutablePointer<OpaquePointer?>?, UnsafeMutablePointer<UnsafePointer<CChar>?>?) -> Int32
        typealias StepFn = @convention(c) (OpaquePointer?) -> Int32
        typealias FinalizeFn = @convention(c) (OpaquePointer?) -> Int32
        typealias ErrMsgFn = @convention(c) (OpaquePointer?) -> UnsafePointer<CChar>?

        let open: OpenFn
        let close: CloseFn
        let prepare: PrepareFn
        let step: StepFn
        let finalize: FinalizeFn
        let errmsg: ErrMsgFn
        let columnText: ColumnTextFn

        typealias ColumnTextFn = @convention(c) (OpaquePointer?, Int32) -> UnsafePointer<UInt8>?

        init?() {
            guard let library = dlopen("/usr/lib/libsqlite3.dylib", RTLD_NOW) else { return nil }
            func symbol<T>(_ name: String, as type: T.Type) -> T? {
                guard let pointer = dlsym(library, name) else { return nil }
                return unsafeBitCast(pointer, to: T.self)
            }
            guard let open = symbol("sqlite3_open_v2", as: OpenFn.self),
                  let close = symbol("sqlite3_close", as: CloseFn.self),
                  let prepare = symbol("sqlite3_prepare_v2", as: PrepareFn.self),
                  let step = symbol("sqlite3_step", as: StepFn.self),
                  let finalize = symbol("sqlite3_finalize", as: FinalizeFn.self),
                  let errmsg = symbol("sqlite3_errmsg", as: ErrMsgFn.self),
                  let columnText = symbol("sqlite3_column_text", as: ColumnTextFn.self) else { return nil }
            self.open = open
            self.close = close
            self.prepare = prepare
            self.step = step
            self.finalize = finalize
            self.errmsg = errmsg
            self.columnText = columnText
        }
    }

    /// Runs `PRAGMA quick_check` on the database at `path`. Read-only open:
    /// a WAL-mode database is checked through its committed state without
    /// writing; -wal/-shm siblings are only ever READ here.
    static func quickCheck(path: String, grant: Int64? = nil) throws -> Report {
        guard let bridge = Bridge() else { throw IntegrityError.bridgeUnavailable }
        let handleOwned = grant == nil
        let handle = grant ?? ContainerStore.grantContainerAccess((path as NSString).deletingLastPathComponent)
        defer {
            if handleOwned, handle >= 0 { SandboxAccess.release(handle) }
        }

        var db: OpaquePointer?
        let openFlags: Int32 = 0x0000_0001 /* SQLITE_OPEN_READONLY */
        guard bridge.open(path, &db, openFlags, nil) == 0, let db = db else {
            let message = bridge.errmsg(db).map { String(cString: $0) } ?? "open failed"
            bridge.close(db)
            throw IntegrityError.openFailed(message)
        }
        defer { bridge.close(db) }

        var statement: OpaquePointer?
        guard bridge.prepare(db, "PRAGMA quick_check", Int32(-1), &statement, nil) == 0 else {
            let message = bridge.errmsg(db).map { String(cString: $0) } ?? "prepare failed"
            throw IntegrityError.queryFailed(message)
        }
        defer { bridge.finalize(statement) }

        var problems: [String] = []
        var budget = maxRows
        while budget > 0 {
            let rc = bridge.step(statement)
            if rc == 101 /* DONE */ { break }
            guard rc == 100 /* ROW */ else {
                let message = bridge.errmsg(db).map { String(cString: $0) } ?? "step failed"
                throw IntegrityError.queryFailed(message)
            }
            budget -= 1
            // quick_check yields a single TEXT column per row.
            if let bytes = bridge.columnText(statement, 0) {
                problems.append(String(cString: bytes))
            }
        }
        if problems.isEmpty {
            return Report(status: "ok", problemCount: 0)
        }
        return Report(status: problems.joined(separator: "\n"),
                      problemCount: problems.count)
    }
}
