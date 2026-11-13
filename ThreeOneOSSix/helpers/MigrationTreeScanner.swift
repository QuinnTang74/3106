import Foundation

/// Tree snapshot for migration prepare. Walks each mapped source root,
/// recording identity (inode/device), size, and mtime per entry so the
/// engine's optimistic concurrency checks and resume validation have a
/// baseline. Symlinks are refused outright — following one inside a
/// foreign container could write outside the migration scope.
enum MigrationTreeScanner {

    enum ScanError: Error, Equatable {
        case symlinkRejected(String)
        case specialFileRejected(String)
        case scanFailed(String)
    }

    struct ScanResult {
        var files: [MigrationFileRecord] = []
        var totalBytes: Int64 = 0
    }

    /// Walks every mapping root and returns files in deterministic order
    /// (mapping order, then lexicographic within a tree). Directory records
    /// are emitted before their contents so the engine can mkdir first.
    /// All record paths are CONTAINER-RELATIVE (keyed by mapping roots), the
    /// convention the engine's remap and resume validation rely on.
    static func scan(containerPath: String, mappings: [MigrationMapping],
                     fileManager: FileManager = .default) throws -> ScanResult {
        var result = ScanResult()
        for mapping in mappings {
            let root = joinRoot(containerPath, mapping.sourceRelativePath)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: root, isDirectory: &isDir) else {
                continue // vanished between selection and prepare: skip quietly
            }
            if isDir.boolValue {
                result.files.append(try statEntry(root, relative: mapping.sourceRelativePath))
                try walk(directory: root, relativePrefix: mapping.sourceRelativePath,
                         into: &result, fileManager: fileManager)
            } else {
                result.files.append(try statEntry(root, relative: mapping.sourceRelativePath))
            }
        }
        result.totalBytes = result.files.reduce(0) { $0 + ($1.isDirectory ? 0 : $1.byteCount) }
        return result
    }

    private static func walk(directory: String, relativePrefix: String,
                             into result: inout ScanResult,
                             fileManager: FileManager) throws {
        let contents: [String]
        do {
            contents = try fileManager.contentsOfDirectory(atPath: directory).sorted()
        } catch {
            throw ScanError.scanFailed("\(directory): \(error.localizedDescription)")
        }
        for name in contents {
            let fullPath = (directory as NSString).appendingPathComponent(name)
            var isSymlink = false
            if let lstat = lstatPoint(fullPath) {
                isSymlink = (lstat.st_mode & S_IFMT) == S_IFLNK
            }
            if isSymlink {
                throw ScanError.symlinkRejected(relativePrefix + "/" + name)
            }

            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: fullPath, isDirectory: &isDir) else {
                continue
            }
            let relative = relativePrefix + "/" + name
            if isDir.boolValue {
                result.files.append(try statEntry(fullPath, relative: relative))
                try walk(directory: fullPath, relativePrefix: relative,
                         into: &result, fileManager: fileManager)
            } else {
                result.files.append(try statEntry(fullPath, relative: relative))
            }
        }
    }

    /// Records one entry at an explicitly given container-relative path.
    private static func statEntry(_ path: String, relative: String) throws -> MigrationFileRecord {
        guard let st = lstatPoint(path) else {
            throw ScanError.scanFailed("lstat failed: \(path)")
        }
        let mode = st.st_mode & S_IFMT
        if mode != S_IFDIR && mode != S_IFREG {
            throw ScanError.specialFileRejected(path)
        }
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return MigrationFileRecord(
            relativePath: relative,
            isDirectory: isDir.boolValue,
            byteCount: isDir.boolValue ? 0 : Int64(st.st_size),
            inode: UInt64(st.st_ino),
            device: UInt64(st.st_dev),
            modifiedAt: Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec)),
            sha256: nil
        )
    }

    private static func lstatPoint(_ path: String) -> stat? {
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        return st
    }

    /// Joins a container root with a mapping path, rejecting traversal.
    static func joinRoot(_ containerPath: String, _ relative: String) -> String {
        let cleaned = relative.split(separator: "/", omittingEmptySubsequences: true)
            .filter { $0 != ".." && $0 != "." }
        let root = (containerPath as NSString).standardizingPath
        guard !cleaned.isEmpty else { return root }
        return (root as NSString).appendingPathComponent(cleaned.joined(separator: "/"))
    }

    /// Space estimate: bytes to add on the target volume plus working headroom
    /// (the largest single file must fit twice: partial temp + final).
    static func spaceEstimate(bytesToAdd: Int64, largestFile: Int64) -> Int64 {
        bytesToAdd + max(0, largestFile) + 32 * 1_048_576
    }
}
