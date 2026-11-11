import Foundation
import Darwin

/// Cooperative cancellation shared by long container/file scans.
final class ScanToken {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

/// Fast arbitrary-path directory enumeration by brute-forcing inodes and
/// resolving them with `fsgetpath`. Ported from forcequitOS/worse_query's
/// `pathleak.m` (GPL-3.0-or-later); see NOTICE.md.
enum Pathleak {
    static func list(
        directory: String,
        maxInode: UInt64 = 2_000_000,
        startInode: UInt64 = 1,
        token: ScanToken? = nil,
        progress: ((Int64, Int64) -> Void)? = nil
    ) -> [String] {
        var dir = directory
        while dir.count > 1 && dir.hasSuffix("/") {
            dir.removeLast()
        }
        guard !dir.isEmpty else { return [] }

        var filesystem = statfs()
        if statfs(dir, &filesystem) != 0 {
            if statfs("/private/var", &filesystem) != 0,
               statfs("/var", &filesystem) != 0 {
                return []
            }
        }
        var fsid = filesystem.f_fsid

        var prefix = dir
        if prefix.hasPrefix("/private/") {
            prefix.removeFirst("/private".count)
        }

        guard startInode >= 1, maxInode >= startInode else { return [] }
        let total = Int64(maxInode - startInode + 1)
        var result: [String] = []
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        var inode = startInode

        while inode <= maxInode {
            if token?.isCancelled == true { break }

            let length = buffer.withUnsafeMutableBufferPointer { pointer in
                fsgetpath(pointer.baseAddress, pointer.count, &fsid, inode)
            }
            if length > 0 {
                var path = buffer.withUnsafeBufferPointer { pointer in
                    String(cString: pointer.baseAddress!)
                }
                if path.hasPrefix("/private/") {
                    path.removeFirst("/private".count)
                }
                if path.hasPrefix(prefix) {
                    let rest = path.dropFirst(prefix.count)
                    if rest.first == "/", !rest.dropFirst().contains("/") {
                        result.append(path)
                    }
                }
            }

            if let progress, inode % 4_096 == 0 || inode == maxInode {
                progress(Int64(inode - startInode + 1), total)
            }
            inode &+= 1
        }

        if let progress {
            let done = Int64(min(inode, maxInode) - startInode + 1)
            progress(max(0, done), total)
        }
        return result
    }
}