import Foundation

/// Configuration rename audit (design inspired by WCMigrate's
/// ConfigurationRenaming; independent implementation).
///
/// After a folder migration or config-set application, plists copied into
/// the target container can still reference the SOURCE app's container by
/// absolute path (group containers, document paths saved by the app). This
/// auditor scans text-representable plists for such references and builds an
/// approval list: each finding maps an old prefix to the target's own
/// container path. The user approves or rejects per file; approved files are
/// rewritten atomically with a version snapshot.
enum MigrationRenameAuditor {

    struct Finding: Identifiable, Hashable {
        let id: UUID
        let plistRelativePath: String
        let oldPrefix: String
        let newPrefix: String
        /// Number of string occurrences of oldPrefix inside the file.
        let occurrenceCount: Int
    }

    enum AuditError: Error, Equatable {
        case plistUnreadable(String)
        case containerMissing
    }

    // MARK: - Scan

    /// Walks the target container's Preferences + Documents for .plist files
    /// whose serialized content contains the source container path. Returns
    /// one finding per file (deduplicated).
    static func audit(sourceContainerPath: String, targetContainerPath: String,
                      token: CancellationToken? = nil,
                      fileManager: FileManager = .default) throws -> [Finding] {
        guard fileManager.fileExists(atPath: targetContainerPath) else {
            throw AuditError.containerMissing
        }
        var findings: [Finding] = []
        for searchRoot in ["Library/Preferences", "Documents"] {
            let root = (targetContainerPath as NSString).appendingPathComponent(searchRoot)
            guard fileManager.fileExists(atPath: root) else { continue }
            var plistPaths: [String] = []
            collectPlists(root, into: &plistPaths, fm: fileManager)
            for path in plistPaths {
                try token?.check()
                let data = try? Data(contentsOf: URL(fileURLWithPath: path))
                guard let data = data,
                      data.range(of: Data(sourceContainerPath.utf8)) != nil else { continue }
                let relative = String(path.dropFirst(targetContainerPath.count + 1))
                findings.append(Finding(
                    id: UUID(),
                    plistRelativePath: relative,
                    oldPrefix: sourceContainerPath,
                    newPrefix: targetContainerPath,
                    occurrenceCount: occurrenceCount(of: sourceContainerPath, in: data)
                ))
            }
        }
        return findings
    }

    // MARK: - Apply

    /// Rewrites approved files, replacing the old container prefix with the
    /// target's. Each write goes through BackupCenter's verified writer so a
    /// version snapshot exists before the bytes change.
    static func apply(_ findings: [Finding],
                      targetContainerPath: String,
                      token: CancellationToken? = nil,
                      fileManager: FileManager = .default) throws {
        for finding in findings {
            try token?.check()
            let fullPath = (targetContainerPath as NSString)
                .appendingPathComponent(finding.plistRelativePath)
            guard var data = try? Data(contentsOf: URL(fileURLWithPath: fullPath)) else {
                throw AuditError.plistUnreadable(finding.plistRelativePath)
            }
            let oldBytes = Data(finding.oldPrefix.utf8)
            let newBytes = Data(finding.newPrefix.utf8)
            data = replacing(oldBytes, with: newBytes, in: data)
            try VerifiedFileWriter.write(data, to: URL(fileURLWithPath: fullPath),
                                         feature: .migration, reason: "rename-audit")
        }
        if !findings.isEmpty {
            ActivityHistory.log(.write, feature: "rename-audit",
                                "\(findings.count) plist files path-renamed")
        }
    }

    // MARK: - Primitives

    private static func collectPlists(_ root: String, into result: inout [String], fm: FileManager) {
        guard let names = try? fm.contentsOfDirectory(atPath: root) else { return }
        for name in names {
            let full = (root as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: full, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                collectPlists(full, into: &result, fm: fm)
            } else if name.hasSuffix(".plist") {
                result.append(full)
            }
        }
    }

    private static func occurrenceCount(of needle: String, in data: Data) -> Int {
        let bytes = Data(needle.utf8)
        guard !bytes.isEmpty else { return 0 }
        var count = 0
        var searchRange = data.startIndex..<data.endIndex
        while let found = data.range(of: bytes, options: [], in: searchRange) {
            count += 1
            searchRange = found.upperBound..<data.endIndex
        }
        return count
    }

    private static func replacing(_ old: Data, with new: Data, in source: Data) -> Data {
        guard !old.isEmpty else { return source }
        var result = Data()
        var searchRange = source.startIndex..<source.endIndex
        var cursor = source.startIndex
        while let found = source.range(of: old, options: [], in: searchRange) {
            result.append(source[cursor..<found.lowerBound])
            result.append(new)
            cursor = found.upperBound
            searchRange = found.upperBound..<source.endIndex
        }
        result.append(source[cursor..<source.endIndex])
        return result
    }
}
