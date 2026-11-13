import Foundation
import CryptoKit
import Darwin

/// Single-file write primitives for the migration engine. Every payload file
/// lands through the same pipeline: APFS clone when possible, streaming copy
/// with running SHA-256 otherwise, fsync, optimistic-concurrency re-check of
/// the destination, atomic rename. Interruptions leave at most one known
/// `.3106-partial` temp file, journaled by the checkpoint store.
enum MigrationFileCopy {

    enum CopyError: Error, Equatable {
        case sourceChanged(String)
        case destinationChanged(String)
        case cloneAndCopyFailed(String)
        case renameFailed(String)
        case swapUnsupported(String)
        case swapFailed(String)
    }

    static let partialSuffix = ".3106-partial"

    // MARK: - Clone + stream copy

    /// Copies `source` onto the caller-chosen `tempPath` (must not exist).
    /// The caller owns journaling, CAS and rename ordering via `commitTemp`.
    /// Returns the SHA-256 of the copied content.
    @discardableResult
    static func copyToTemp(source: String, tempPath: String,
                           token: CancellationToken?) throws -> String {
        let fm = FileManager.default

        let srcFD = open(source, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard srcFD >= 0 else {
            throw CopyError.cloneAndCopyFailed("open(source) failed: \(source) errno \(errno)")
        }
        defer { close(srcFD) }

        let mode = sourceMode(source)
        let dstFD = open(tempPath, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode)
        guard dstFD >= 0 else {
            throw CopyError.cloneAndCopyFailed("open(temp) failed errno \(errno)")
        }
        defer { close(dstFD) }

        var hasher = SHA256()
        // Try APFS clone first: copy-on-write, effectively free for large
        // chat databases. Clone through our descriptor, fsync, then hash the
        // clone by reading it back.
        if fcopyfile(srcFD, dstFD, nil, copyfile_flags_t(COPYFILE_DATA)) == 0 {
            fsync(dstFD)
            let hashFD = open(tempPath, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            if hashFD >= 0 {
                defer { close(hashFD) }
                try hashInto(hasher: &hasher, fd: hashFD, token: token)
            } else {
                try? fm.removeItem(atPath: tempPath)
                throw CopyError.cloneAndCopyFailed("hash open failed errno \(errno)")
            }
        } else {
            // Streaming fallback: 4MB blocks, hash while reading, write while
            // hashing — one pass, no double read.
            var buffer = [UInt8](repeating: 0, count: 4 * 1_048_576)
            while true {
                try token?.check()
                let n = read(srcFD, &buffer, buffer.count)
                if n < 0 {
                    if errno == EINTR { continue }
                    try? fm.removeItem(atPath: tempPath)
                    throw CopyError.cloneAndCopyFailed("read failed errno \(errno)")
                }
                if n == 0 { break }
                hasher.update(data: Data(buffer[0..<n]))
                var offset = 0
                while offset < n {
                    let w = buffer.withUnsafeBytes { raw in
                        write(dstFD, raw.baseAddress!.advanced(by: offset), n - offset)
                    }
                    if w < 0 {
                        if errno == EINTR { continue }
                        try? fm.removeItem(atPath: tempPath)
                        throw CopyError.cloneAndCopyFailed("write failed errno \(errno)")
                    }
                    offset += w
                }
            }
            fsync(dstFD)
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// fsyncs the temp file, re-checks the destination wasn't externally
    /// modified since prepare (CAS via inode/mtime), then renames temp into
    /// place. `expected` is the record for an EXISTING destination being
    /// overwritten; nil = destination should not exist (RENAME_EXCL).
    static func commitTemp(tempPath: String, destination: String,
                           expected: MigrationFileRecord?, token: CancellationToken?) throws {
        try token?.check()
        // CAS the destination BEFORE the swap: if another process recreated
        // or resized it mid-migration, refuse rather than clobber blindly.
        if let expected = expected {
            guard let st = lstatPoint(destination) else {
                try? FileManager.default.removeItem(atPath: tempPath)
                throw CopyError.destinationChanged(destination)
            }
            let nowMtime = TimeInterval(st.st_mtimespec.tv_sec)
            if UInt64(st.st_ino) != expected.inode ||
                UInt64(st.st_dev) != expected.device ||
                nowMtime != expected.modifiedAt.timeIntervalSince1970 {
                try? FileManager.default.removeItem(atPath: tempPath)
                throw CopyError.destinationChanged(destination)
            }
            // Overwrite: plain rename is atomic on APFS and replaces the target.
            if rename(tempPath, destination) != 0 {
                let err = errno
                try? FileManager.default.removeItem(atPath: tempPath)
                throw CopyError.renameFailed("errno \(err)")
            }
        } else {
            // Destination must not exist: RENAME_EXCL makes that a kernel check.
            if renamex_np(tempPath, destination, UInt32(RENAME_EXCL)) != 0 {
                let err = errno
                try? FileManager.default.removeItem(atPath: tempPath)
                if err == EEXIST {
                    throw CopyError.destinationChanged("unexpectedly exists: \(destination)")
                }
                throw CopyError.renameFailed("errno \(err)")
            }
        }
    }

    // MARK: - Atomic exchange

    /// Atomically swaps two paths. Never degrades to copy: ENOTSUP / EXDEV
    /// surfaces as swapUnsupported so the UI can tell the user this volume
    /// cannot exchange.
    static func swapPaths(_ pathA: String, _ pathB: String) throws {
        let result = renamex_np(pathA, pathB, UInt32(RENAME_SWAP))
        if result == 0 { return }
        let err = errno
        // ENOTSUP and EOPNOTSUPP are aliases on Darwin — listing both would
        // be a duplicate-case compile error.
        switch err {
        case ENOTSUP, EXDEV, EINVAL:
            throw CopyError.swapUnsupported("errno \(err) — volume cannot RENAME_SWAP")
        default:
            throw CopyError.swapFailed("errno \(err)")
        }
    }

    // MARK: - Helpers

    private static func sourceMode(_ path: String) -> mode_t {
        var st = stat()
        guard stat(path, &st) == 0 else { return 0o644 }
        return mode_t(st.st_mode & 0o7777)
    }

    private static func lstatPoint(_ path: String) -> stat? {
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        return st
    }

    /// Reads a descriptor in chunks into the hasher. The caller owns fd
    /// lifetime; this function only reads.
    private static func hashInto(hasher: inout SHA256, fd: Int32,
                                 token: CancellationToken?) throws {
        var buffer = [UInt8](repeating: 0, count: 4 * 1_048_576)
        while true {
            try token?.check()
            let n = read(fd, &buffer, buffer.count)
            if n < 0 {
                if errno == EINTR { continue }
                throw CopyError.cloneAndCopyFailed("hash read failed errno \(errno)")
            }
            if n == 0 { break }
            hasher.update(data: Data(buffer[0..<n]))
        }
    }
}
