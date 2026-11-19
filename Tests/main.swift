import Foundation

// WallpaperLabModels calls the app-global log(); the harness has no UI, so
// route the lines to stderr instead.
func log(_ msg: String) {
    fputs("[3106] \(msg)\n", stderr)
}

// Harness stubs for the sandbox-grant chain: -1 means "no grant needed" and
// release() honors that guard, so the wallpaper scanner exercises its pure
// path logic without the device-only worse_query backend.
enum ContainerStore {
    static func grantContainerAccess(_ containerPath: String) -> Int64 { -1 }
}

enum SandboxAccess {
    static func release(_ handle: Int64) {}
}

// Standalone verification for the support matrix. Run with:
//   bash Tests/run_policy_tests.sh
//
// The device-only paths (worse_query, container-manager queries) are validated
// on hardware; this harness covers the pure policy logic that decides which
// backend is selected for each iOS version.

var checks = 0
var failures = 0

func expect(_ condition: Bool, _ message: String) {
    checks += 1
    if !condition {
        failures += 1
        fputs("FAIL: \(message)\n", stderr)
    }
}

func expectFalse(_ condition: Bool, _ message: String) {
    expect(!condition, message)
}

/// Asserts a throwing call fails with exactly the expected policy error.
func expectThrows(
    _ message: String,
    expected: NotificationSoundPolicy.ValidationError,
    body: () throws -> Void
) {
    checks += 1
    do {
        try body()
        failures += 1
        fputs("FAIL: \(message) — no error thrown\n", stderr)
    } catch let error as NotificationSoundPolicy.ValidationError where error == expected {
        // pass
    } catch {
        failures += 1
        fputs("FAIL: \(message) — unexpected error \(error)\n", stderr)
    }
}

/// Asserts a throwing call succeeds (no error, no value to compare).
func expectNoThrow(_ message: String, body: () throws -> Void) {
    checks += 1
    do {
        try body()
    } catch {
        failures += 1
        fputs("FAIL: \(message) — threw \(error)\n", stderr)
    }
}

// iOS 17 kernel range
expect(ExploitSupportPolicy.supportsKernelExploit(major: 17, minor: 0, patch: 0), "17.0 kernel")
expect(ExploitSupportPolicy.supportsKernelExploit(major: 17, minor: 7, patch: 9), "17.7.x kernel")
expectFalse(ExploitSupportPolicy.supportsKernelExploit(major: 17, minor: 8, patch: 0), "17.8 not kernel")
expectFalse(ExploitSupportPolicy.supportsKernelExploit(major: 16, minor: 7, patch: 0), "16.x not kernel")

// iOS 18 kernel range
expect(ExploitSupportPolicy.supportsKernelExploit(major: 18, minor: 0, patch: 0), "18.0 kernel")
expect(ExploitSupportPolicy.supportsKernelExploit(major: 18, minor: 7, patch: 1), "18.7.1 kernel")
expectFalse(ExploitSupportPolicy.supportsKernelExploit(major: 18, minor: 7, patch: 2), "18.7.2 not kernel")
expectFalse(ExploitSupportPolicy.supportsKernelExploit(major: 18, minor: 7, patch: 5), "18.7.5 not kernel")
expectFalse(ExploitSupportPolicy.supportsKernelExploit(major: 18, minor: 7, patch: 12), "18.7.12 not kernel")
expectFalse(ExploitSupportPolicy.supportsKernelExploit(major: 18, minor: 8, patch: 0), "18.8 not kernel")
expectFalse(ExploitSupportPolicy.supportsKernelExploit(major: 19, minor: 0, patch: 0), "19.0 not kernel")

// F-06 drift guard: the user-facing range string and the enforced boundary
// must describe the same thing. Changing one without the other is exactly the
// mistake this constant was extracted to prevent.
expect(ExploitSupportPolicy.verifiedIOS18Range == "18.0–18.7.1",
       "policy drift: verifiedIOS18Range label is 18.0–18.7.1")
expect(ExploitSupportPolicy.supportsKernelExploit(major: 18, minor: 7, patch: 1),
       "policy drift: the last build named in verifiedIOS18Range must be supported")
expectFalse(ExploitSupportPolicy.supportsKernelExploit(major: 18, minor: 7, patch: 2),
            "policy drift: the first build past verifiedIOS18Range must be rejected")

// The patch constant drives the user-facing explanation; it must name the same
// release that closes the window.
expect(ExploitSupportPolicy.ios18KernelPatchedAt == "18.7.2",
       "policy drift: ios18KernelPatchedAt is 18.7.2")
expect(ExploitSupportPolicy.isIOS18KernelPatched(major: 18, minor: 7, patch: 2),
       "explain: 18.7.2 is the first patched build")
expectFalse(ExploitSupportPolicy.isIOS18KernelPatched(major: 18, minor: 7, patch: 1),
            "explain: 18.7.1 is not patched")
expectFalse(ExploitSupportPolicy.isIOS18KernelPatched(major: 17, minor: 7, patch: 9),
            "explain: iOS 17 is not an iOS 18 patched build")

// Same guard for the 27 row. `verifiedIOS27Range` had drifted to "27.0–27.2.1"
// while the code accepted every 27.2.x: the label claimed a patch boundary
// that `supportsWorseQuery` never enforced. Both the label and the boundary
// are pinned here so that mistake cannot come back silently.
expect(ExploitSupportPolicy.verifiedIOS27Range == "27.0–27.2",
       "policy drift: verifiedIOS27Range label is 27.0–27.2 (no patch boundary)")
expect(ExploitSupportPolicy.supportsWorseQuery(major: 27, minor: 2, patch: 0),
       "policy drift: 27.2.0 must be supported")
expect(ExploitSupportPolicy.supportsWorseQuery(major: 27, minor: 2, patch: 9),
       "policy drift: every 27.2.x patch level is accepted unconditionally")

// The build-gated 27.3 row is a separate constant precisely because its
// boundary is a build number. Pin it too, so a future edit that folds 27.3
// back into the contiguous range above cannot pass CI.
expect(ExploitSupportPolicy.verifiedIOS27BuildGatedRange == "27.3 beta 1",
       "policy drift: build-gated range label is 27.3 beta 1")
expect(ExploitSupportPolicy.verifiedIOS27Builds == ["24C5037i"],
       "policy drift: exactly one 27.3 build is verified (beta 1)")

// bad_query range
expect(ExploitSupportPolicy.supportsBadQuery(major: 26, minor: 0, patch: 0), "26.0 bad_query")
expect(ExploitSupportPolicy.supportsBadQuery(major: 26, minor: 6, patch: 1), "26.6.1 bad_query")
expectFalse(ExploitSupportPolicy.supportsBadQuery(major: 26, minor: 6, patch: 2), "26.6.2 not bad_query")
expectFalse(ExploitSupportPolicy.supportsBadQuery(major: 26, minor: 7, patch: 0), "26.7 not bad_query")

// worse_query range
expectFalse(ExploitSupportPolicy.supportsWorseQuery(major: 26, minor: 6, patch: 9), "26.6.9 not worse_query")
expect(ExploitSupportPolicy.supportsWorseQuery(major: 26, minor: 7, patch: 0), "26.7.0 worse_query")
expect(ExploitSupportPolicy.supportsWorseQuery(major: 26, minor: 7, patch: 2), "26.7.2 worse_query")
expect(ExploitSupportPolicy.supportsWorseQuery(major: 27, minor: 2, patch: 1), "27.2.1 worse_query")
expectFalse(ExploitSupportPolicy.supportsWorseQuery(major: 26, minor: 7, patch: 3), "26.7.3 not worse_query")
expect(ExploitSupportPolicy.supportsWorseQuery(major: 27, minor: 0, patch: 0), "27.0 worse_query")
expect(ExploitSupportPolicy.supportsWorseQuery(major: 27, minor: 2, patch: 0), "27.2 worse_query")
expect(ExploitSupportPolicy.supportsWorseQuery(major: 27, minor: 3, patch: 0, build: "24C5037i"), "27.3 beta 1 worse_query verified on hardware")
expectFalse(ExploitSupportPolicy.supportsWorseQuery(major: 27, minor: 3, patch: 0, build: "24C5049d"), "27.3 beta 2 worse_query patched by Apple")
expectFalse(ExploitSupportPolicy.supportsWorseQuery(major: 27, minor: 3, patch: 0, build: "unknown"), "27.3 unknown build must fail closed")
expectFalse(ExploitSupportPolicy.supportsWorseQuery(major: 27, minor: 3, patch: 1, build: "24C5037i"),
            "27.3.1 must be rejected even with a whitelisted build string: beta 1 is 27.3.0")
expectFalse(ExploitSupportPolicy.supportsWorseQuery(major: 27, minor: 3, patch: 0), "27.3 without build arg must fail closed")
expectFalse(ExploitSupportPolicy.supportsWorseQuery(major: 27, minor: 4, patch: 0, build: "24C5037i"), "27.4 not worse_query")
expectFalse(ExploitSupportPolicy.supportsWorseQuery(major: 28, minor: 0, patch: 0), "28.0 not worse_query")

// Overall support. There is no experimental tier: every accepted combination
// is one of the three enumerated probes, so an unlisted version must be false
// rather than falling through to a catch-all.
expect(ExploitSupportPolicy.isSupported(major: 26, minor: 7, patch: 2, build: "any"), "26.7.2 supported")
expect(ExploitSupportPolicy.isSupported(major: 27, minor: 2, patch: 0, build: "any"), "27.2 supported")
expect(ExploitSupportPolicy.isSupported(major: 27, minor: 3, patch: 0, build: "24C5037i"), "27.3 beta 1 supported")
expectFalse(ExploitSupportPolicy.isSupported(major: 27, minor: 3, patch: 0, build: "24C5049d"), "27.3 beta 2 unsupported after Apple patch")
expectFalse(ExploitSupportPolicy.isSupported(major: 27, minor: 3, patch: 0, build: "any"), "27.3 unknown build unsupported")
expectFalse(ExploitSupportPolicy.isSupported(major: 28, minor: 0, patch: 0, build: "any"), "28.0 unsupported")
expectFalse(ExploitSupportPolicy.isSupported(major: 16, minor: 7, patch: 0, build: "any"), "16.x unsupported")

// MARK: - App data browser regression checks

struct BrowserTestEntry {
    let id: String
    let path: String
}

let testUUID = "12345678-1234-1234-1234-1234567890AB"
expect(
    ContainerPresentationPolicy.classification(bundleID: testUUID) == .unidentified,
    "UUID container classified as unidentified"
)
expect(
    ContainerPresentationPolicy.classification(bundleID: "com.example.app") == .identified,
    "bundle id classified as identified"
)
expect(
    ContainerAccessPolicy.shouldRequestGrant(isRoot: true),
    "root browser requests a container grant"
)
expect(
    ContainerAccessPolicy.shouldRequestGrant(isRoot: false),
    "favorite subdirectory browser still requests a container grant"
)

let identifiedEntry = BrowserTestEntry(
    id: "com.example.app",
    path: "/private/var/mobile/Containers/Data/Application/\(testUUID)"
)
let unidentifiedEntry = BrowserTestEntry(
    id: "87654321-4321-4321-4321-BA0987654321",
    path: "/private/var/mobile/Containers/Data/Application/87654321-4321-4321-4321-BA0987654321"
)

let discoveredMerged = ContainerDiscoveryMerger.merge(
    enumerated: [unidentifiedEntry],
    identified: [identifiedEntry],
    path: { $0.path }
)
expect(discoveredMerged.count == 2, "discovery merger keeps identified and unidentified containers")

let catalogMerged = AppDataCatalogMerger.merge(
    identified: [identifiedEntry],
    fallback: [unidentifiedEntry],
    identifier: { $0.id },
    path: { $0.path }
)
expect(catalogMerged.count == 2, "catalog merger keeps unidentified fallback")

// Synthetic LaunchServices `bdsl` store: one Bundle record (0x250 layout)
// that points at a bundle id, a display name, and an app-data container.
func writeU32(_ data: inout Data, _ offset: Int, _ value: UInt32) {
    data[offset] = UInt8(value & 0xff)
    data[offset + 1] = UInt8((value >> 8) & 0xff)
    data[offset + 2] = UInt8((value >> 16) & 0xff)
    data[offset + 3] = UInt8((value >> 24) & 0xff)
}

func writeString(_ data: inout Data, at offset: Int, id: UInt32, value: String) {
    let bytes = Array(value.utf8)
    writeU32(&data, offset, id)
    writeU32(&data, offset + 4, UInt32(bytes.count))
    data.replaceSubrange((offset + 8)..<(offset + 8 + bytes.count), with: bytes)
}

var store = Data(repeating: 0, count: 0x1000)
store.replaceSubrange(0..<4, with: Data([0x62, 0x64, 0x73, 0x6c])) // "bdsl"
store.replaceSubrange(0x200..<0x208, with: Data("<string>".utf8))

let recordOffset = 0x100
let body = recordOffset + 8
writeU32(&store, recordOffset + 4, 0x250)
writeU32(&store, body + 0x0c, 4)   // string id 1: bundle id
writeU32(&store, body + 0x6c, 8)   // string id 2: bundle name
writeU32(&store, body + 0x74, 12)  // string id 3: display name
writeU32(&store, body + 0x68, 16)  // string id 4: container path
writeU32(&store, body + 0x00, 0)   // no bundle path

writeString(&store, at: 0x300, id: 1, value: "com.example.app")
writeString(&store, at: 0x340, id: 2, value: "Example")
writeString(&store, at: 0x380, id: 3, value: "Example App")
writeString(
    &store,
    at: 0x3C0,
    id: 4,
    value: "/private/var/mobile/Containers/Data/Application/\(testUUID)"
)

let snapshot = LaunchServicesStore.parse(store)
expect(snapshot != nil, "LaunchServices parser accepts a synthetic bdsl store")
if let snapshot {
    expect(
        snapshot.containerBundleIDs.values.contains("com.example.app"),
        "LaunchServices parser maps a container to its bundle id"
    )
    expect(
        snapshot.displayName(forBundleID: "com.example.app") == "Example App",
        "LaunchServices parser decodes the display name"
    )
    expect(snapshot.containerPaths.count == 1, "LaunchServices parser reports one container")
    expect(
        snapshot.bundleID(forContainerPath: identifiedEntry.path) == "com.example.app",
        "LaunchServices snapshot lookup canonicalizes the path"
    )
}

expect(
    LaunchServicesStore.canonicalContainerPath(
        "/var/mobile/Containers/Data/Application/\(testUUID)/"
    ) == "/private/var/mobile/Containers/Data/Application/\(testUUID)",
    "container path canonicalization"
)
expect(
    LaunchServicesStore.isDataContainerPath(identifiedEntry.path),
    "app data container path is recognized"
)
expect(
    LaunchServicesStore.isPath(
        "/private/var/mobile/Containers/Data/Application/\(testUUID)/Library/Caches",
        containedIn: "/var/mobile/Containers/Data/Application/\(testUUID)"
    ),
    "path containment treats /var and /private/var as the same tree"
)
expectFalse(
    LaunchServicesStore.isPath(
        "/private/var/mobile/Containers/Data/Application/\(testUUID)X",
        containedIn: "/var/mobile/Containers/Data/Application/\(testUUID)"
    ),
    "path containment does not match a sibling prefix"
)

// URL-level containment must not depend on resolvingSymlinksInPath(): inside
// the sandbox that call can stop early and return mixed spellings for the
// same tree (issue #2), so every raw/resolved spelling pair has to pass.
do {
    let root = URL(fileURLWithPath: "/var/mobile/Containers/Data/Application/\(testUUID)")
        .appendingPathComponent("Library/Application Support/WallpaperLab/Packages/.importing-x/Extracted", isDirectory: true)
    let child = URL(fileURLWithPath: "/private/var/mobile/Containers/Data/Application/\(testUUID)")
        .appendingPathComponent("Library/Application Support/WallpaperLab/Packages/.importing-x/Extracted/descriptors", isDirectory: true)
    expect(
        WallpaperLayoutScanner.isContained(child, in: root),
        "URL containment accepts /private/var child under /var root (issue #2 mix)"
    )
    let outside = root.deletingLastPathComponent()
        .appendingPathComponent("Other/elsewhere", isDirectory: true)
    expectFalse(
        WallpaperLayoutScanner.isContained(outside, in: root),
        "URL containment still rejects paths outside the root"
    )
}

// MARK: - Favorites store checks

let favoritesSuite = "3106.favorites.tests.\(UUID().uuidString)"
if let defaults = UserDefaults(suiteName: favoritesSuite) {
    defaults.removePersistentDomain(forName: favoritesSuite)
    let favorites = FileFavoritesStore(defaults: defaults)
    favorites.add(
        path: "/var/mobile/Containers/Data/Application/\(testUUID)/",
        name: "Test Folder"
    )
    expect(favorites.favorites.count == 1, "favorites add stores one item")
    expect(
        favorites.contains(
            path: "/private/var/mobile/Containers/Data/Application/\(testUUID)"
        ),
        "favorites normalize /var and /private/var"
    )
    expect(
        favorites.contains(
            path: "/var/mobile/Containers/Data/Application/\(testUUID)/"
        ),
        "favorites tolerate a trailing slash"
    )

    let reloadedFavorites = FileFavoritesStore(defaults: defaults)
    expect(reloadedFavorites.favorites.count == 1, "favorites persist across relaunch")

    reloadedFavorites.add(
        path: "/var/mobile/Containers/Data/Application/\(testUUID)",
        name: "Duplicate"
    )
    expect(reloadedFavorites.favorites.count == 1, "favorites dedupe the same path")

    reloadedFavorites.remove(
        path: "/var/mobile/Containers/Data/Application/\(testUUID)"
    )
    expect(reloadedFavorites.favorites.isEmpty, "favorites remove deletes the entry")
    defaults.removePersistentDomain(forName: favoritesSuite)
} else {
    expect(false, "favorites test defaults unavailable")
}

expect(
    FileFavoriteContainerRoot.containerPath(
        for: "/private/var/mobile/Containers/Data/Application/\(testUUID)/Documents"
    ) == "/private/var/mobile/Containers/Data/Application/\(testUUID)",
    "favorite container root resolves an application folder"
)
expect(
    FileFavoriteContainerRoot.containerPath(
        for: "/private/var/mobile/Containers/Shared/AppGroup/\(testUUID)/Library"
    ) == "/private/var/mobile/Containers/Shared/AppGroup/\(testUUID)",
    "favorite container root resolves an app group folder"
)
expect(
    FileFavoriteContainerRoot.containerPath(
        for: "/private/var/mobile/Library/Preferences"
    ) == nil,
    "favorite container root ignores non-container paths"
)

// MARK: - Cleaner incremental callbacks

// Shape-compatible stand-in for the real type in LimitedCleanerService.
// CleanerCatalog only needs these fields for its pure scanning loop.
struct LimitedCleanerUsage: Equatable {
    let cacheBytes: Int64
    let temporaryBytes: Int64
    let removableItemCount: Int

    var totalBytes: Int64 { cacheBytes + temporaryBytes }
}

let cleanerApplications = [
    CleanerResolvedApplication(
        bundleID: "com.example.one",
        name: "One",
        containerPath: "/private/var/mobile/Containers/Data/Application/\(testUUID)",
        version: "1.0"
    ),
    CleanerResolvedApplication(
        bundleID: "com.example.two",
        name: "Two",
        containerPath: "/private/var/mobile/Containers/Data/Application/\(testUUID)",
        version: "1.0"
    ),
    CleanerResolvedApplication(
        bundleID: "com.example.three",
        name: "Three",
        containerPath: "/private/var/mobile/Containers/Data/Application/\(testUUID)",
        version: "1.0"
    ),
]
var cleanerScanned = Set<String>()
var cleanerApplicationCallbacks: [String] = []
var cleanerRecordCallbacks: [String] = []
let cleanerRecords = CleanerCatalog.scanNewApplications(
    cleanerApplications,
    scannedBundleIDs: &cleanerScanned,
    shouldIncludeBundleID: { _ in true },
    activateContainer: { $0.containerPath },
    isValidContainerPath: { _ in true },
    usageForContainer: { _ in
        LimitedCleanerUsage(cacheBytes: 10, temporaryBytes: 2, removableItemCount: 1)
    },
    onApplication: { cleanerApplicationCallbacks.append($0) },
    onRecord: { cleanerRecordCallbacks.append($0.bundleID) }
)
expect(cleanerApplicationCallbacks.count == 3, "cleaner reports every examined app")
expect(cleanerRecordCallbacks.count == 3, "cleaner reports every app with removable data")
expect(cleanerRecords.count == 3, "cleaner returns every record")

var cleanerEmptyScanned = Set<String>()
var cleanerEmptyApplications: [String] = []
let cleanerEmptyRecords = CleanerCatalog.scanNewApplications(
    [cleanerApplications[0]],
    scannedBundleIDs: &cleanerEmptyScanned,
    shouldIncludeBundleID: { _ in true },
    activateContainer: { $0.containerPath },
    isValidContainerPath: { _ in true },
    usageForContainer: { _ in
        LimitedCleanerUsage(cacheBytes: 0, temporaryBytes: 0, removableItemCount: 0)
    },
    onApplication: { cleanerEmptyApplications.append($0) },
    onRecord: { _ in }
)
expect(cleanerEmptyApplications.count == 1, "cleaner still reports an app with no removable data")
expect(cleanerEmptyRecords.isEmpty, "cleaner does not return an empty record")
expect(cleanerEmptyScanned.isEmpty, "cleaner does not mark an empty app as scanned")

// LaunchServices fast container catalog: build, filter and disk cache.
do {
    let appA = "/private/var/mobile/Containers/Data/Application/11111111-1111-1111-1111-111111111111"
    let appB = "/private/var/mobile/Containers/Data/Application/22222222-2222-2222-2222-222222222222"
    let plugin = "/private/var/mobile/Containers/Data/PluginKitPlugin/33333333-3333-3333-3333-333333333333"
    let snapshot = LaunchServicesSnapshot(
        containerBundleIDs: [
            appA: "com.example.alpha",
            appB: "com.example.beta",
            plugin: "com.example.alpha.widget"
        ],
        displayNames: [
            "com.example.alpha": "Alpha",
            "com.example.beta": "Beta",
            "com.example.alpha.widget": "Alpha Widget"
        ],
        bundleNames: [:],
        containerPaths: [appA, appB, plugin, appB],
        bundlePaths: [:],
        layoutLabel: "test",
        mappedContainerCount: 3,
        decodedNameCount: 3
    )
    let catalog = ContainerCatalogBuilder.build(
        from: snapshot,
        signature: "sig-1",
        osBuild: "27.0"
    )
    expect(catalog.entries.count == 3, "catalog keeps each container once")
    expect(catalog.entries.contains { $0.bundleID == "com.example.alpha" && $0.displayName == "Alpha" },
           "catalog decodes display names")
    expect(catalog.entries.contains { $0.kind == .extensionContainer && $0.bundleID == "com.example.alpha.widget" },
           "catalog marks plugin containers")

    let catalogRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("3106-catalog-tests-\(UUID().uuidString).json")
    do {
        try ContainerCatalogCache.save(catalog, rootURL: catalogRoot)
        let loaded = ContainerCatalogCache.load(signature: "sig-1", rootURL: catalogRoot)
        expect(loaded?.entries.count == 3, "catalog cache round-trips")
        expect(ContainerCatalogCache.load(signature: "other", rootURL: catalogRoot) == nil,
               "catalog cache rejects a different store signature")
        ContainerCatalogCache.clear(rootURL: catalogRoot)
    } catch {
        expect(false, "catalog cache test failed: \(error)")
    }
}

// Backup center: originals, versions, verified writes, restore and journals.
do {
    let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("3106-backup-tests-\(UUID().uuidString)", isDirectory: true)
    let center = BackupCenter(rootURL: root)
    let fileManager = FileManager.default
    let target = root.appendingPathComponent("target.txt")
    try Data("original".utf8).write(to: target)

    let original = try center.recordOriginalIfNeeded(target: target, feature: .file, reason: "test")
    expect(original.kind == .original, "backup records the first original")
    expect(original.sha256 == BackupCenter.hashData(Data("original".utf8)), "original hash matches")
    let originalAgain = try center.recordOriginalIfNeeded(target: target, feature: .file, reason: "again")
    expect(originalAgain.id == original.id, "original snapshot is immutable")

    let version = try center.createVersionSnapshot(target: target, feature: .file, reason: "before write")
    expect(version.kind == .version, "version snapshot is recorded")
    expect(version.sha256 == BackupCenter.hashData(Data("original".utf8)), "version holds the pre-write content")

    try VerifiedFileWriter.write(
        Data("updated".utf8),
        to: target,
        feature: .file,
        reason: "test write",
        center: center
    )
    expect((try? String(contentsOf: target, encoding: .utf8)) == "updated", "verified writer updates the file")

    try center.restore(original)
    expect((try? String(contentsOf: target, encoding: .utf8)) == "original", "restore returns the original content")

    try center.delete(version)
    expect(!center.records().contains { $0.id == version.id }, "version backup can be deleted")

    do {
        try center.delete(original)
        expect(false, "original backups cannot be deleted")
    } catch {
        expect(true, "original backups cannot be deleted")
    }

    let manual = try center.manualBackup(target: target, feature: .file, label: "manual")
    expect(manual.kind == .manual, "manual backup is recorded")

    let journalTarget = root.appendingPathComponent("journal.txt")
    try Data("before".utf8).write(to: journalTarget)
    let journalOriginal = try center.recordOriginalIfNeeded(
        target: journalTarget,
        feature: .file,
        reason: "journal"
    )
    let journalID = try center.beginJournal(
        target: journalTarget,
        feature: .file,
        backupRecordID: journalOriginal.id,
        reason: "crash simulation"
    )
    expect(center.pendingJournals().contains { $0.id == journalID }, "journal is listed as pending")
    try Data("after".utf8).write(to: journalTarget)
    let recovered = center.recoverPendingJournals()
    expect(recovered >= 1, "pending journal is recovered")
    expect((try? String(contentsOf: journalTarget, encoding: .utf8)) == "before",
           "journal recovery restores the backup")

    let symlink = root.appendingPathComponent("link.txt")
    try fileManager.createSymbolicLink(atPath: symlink.path, withDestinationPath: target.path)
    do {
        try VerifiedFileWriter.write(
            Data("x".utf8),
            to: symlink,
            feature: .file,
            reason: "symlink",
            center: center
        )
        expect(false, "verified writer refuses symlinks")
    } catch {
        expect(true, "verified writer refuses symlinks")
    }

    try? fileManager.removeItem(at: root)
} catch {
    expect(false, "backup center test failed: \(error)")
}

// Cleaner safety policy: protected-path blacklist with component prefixes.
do {
    // Core blacklist entries are always protected.
    for protected in [
        "/var/db", "/private/var/db", "/var/db/uuidtext",
        "/var/mobile/Library/Caches", "/var/mobile/Library/Safari",
        "/private/var/containers/Data/System",
        "/private/var/containers/Shared/SystemGroup",
        "/private/var/mobile/Containers/Data/InternalDaemon",
    ] {
        expect(CleanerSafetyPolicy.isProtectedSystemPath(protected), "protected: \(protected)")
    }

    // Component-prefix matching must not over-match sibling names.
    expectFalse(CleanerSafetyPolicy.isProtectedSystemPath("/var/database"),
                "sibling /var/database is not /var/db")
    expectFalse(CleanerSafetyPolicy.isProtectedSystemPath("/var/db2/x"),
                "sibling /var/db2/x is not /var/db")

    // Anything inside a protected tree is protected too.
    expect(CleanerSafetyPolicy.isProtectedSystemPath("/var/db/uuidtext/deep/file"),
           "descendant of /var/db/uuidtext is protected")

    // App containers are fair game for the cleaner.
    expectFalse(CleanerSafetyPolicy.isProtectedSystemPath(
        "/var/mobile/Containers/Data/Application/ABC123/Library/Caches"),
        "app container caches are cleanable")

    // Relative paths, "/" and traversal components are rejected outright.
    expect(CleanerSafetyPolicy.isProtectedSystemPath("relative/path"),
           "relative path treated as protected (refused)")
    expect(CleanerSafetyPolicy.isProtectedSystemPath("/"), "root refused")
    expect(CleanerSafetyPolicy.isProtectedSystemPath("/var/mobile/Containers/../db"),
           "traversal component refused")
}

// Cleaner safety policy: planned target construction.
do {
    let root = "/var/mobile/Containers/Data/Application/ABC123"
    let ok = CleanerSafetyPolicy.PlannedTarget.build(
        containerRoot: root, relativePath: "Library/Caches"
    )
    expect(ok != nil, "planned target builds for allowlist path")
    expect(ok?.absolutePath == root + "/Library/Caches", "planned target path join")

    expect(CleanerSafetyPolicy.PlannedTarget.build(
        containerRoot: root, relativePath: "../../etc") == nil,
        "traversal relative path refused")
    expect(CleanerSafetyPolicy.PlannedTarget.build(
        containerRoot: root, relativePath: "") == nil,
        "empty relative path refused")
}

// Cleaner safety policy: identity snapshots (TOCTOU protection).
do {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("3106-policy-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("probe.txt")
    try Data("v1".utf8).write(to: file)

    let snapshot = CleanerSafetyPolicy.FileIdentitySnapshot.capture(atPath: file.path)
    expect(snapshot.existed, "snapshot captures existing file")
    expect(snapshot.matchesCurrentPath(file.path), "unchanged file keeps identity")

    // Rewriting via a delete+recreate cycle changes the inode.
    try FileManager.default.removeItem(at: file)
    try Data("v2".utf8).write(to: file)
    expectFalse(snapshot.matchesCurrentPath(file.path),
                "recreated file has a new identity")

    // A snapshot of a missing path refuses an appearing file.
    let ghost = CleanerSafetyPolicy.FileIdentitySnapshot.capture(
        atPath: dir.appendingPathComponent("ghost.txt").path
    )
    expectFalse(ghost.existed, "missing file snapshot")
    try Data("x".utf8).write(to: dir.appendingPathComponent("ghost.txt"))
    expectFalse(ghost.matchesCurrentPath(dir.appendingPathComponent("ghost.txt").path),
                "file that appeared after snapshot is treated as changed")

    try? FileManager.default.removeItem(at: dir)
} catch {
    expect(false, "identity snapshot test failed: \(error)")
}

// Cleaner safety policy: three-stage confirmation gate ordering.
do {
    let gate = CleanerSafetyPolicy.ConfirmationGate()

    // Authorizing without the earlier stages must fail.
    expectFalse(gate.authorize(operationID: "op-1"), "authorize before begin fails")
    expectFalse(gate.acknowledgeScope(operationID: "op-1"), "ack before begin fails")

    expect(gate.begin(operationID: "op-1"), "begin accepts first operation")
    expectFalse(gate.begin(operationID: "op-2"), "begin rejects concurrent operation")

    // Cross-operation ids are refused at every stage.
    expectFalse(gate.acknowledgeScope(operationID: "op-2"), "ack with wrong id fails")
    expect(gate.acknowledgeScope(operationID: "op-1"), "ack with right id passes")
    expectFalse(gate.authorize(operationID: "op-2"), "authorize with wrong id fails")
    expect(gate.authorize(operationID: "op-1"), "authorize in order passes")

    gate.finish(operationID: "op-1")
    expect(gate.begin(operationID: "op-2"), "gate returns to idle after finish")

    gate.cancel()
    expect(gate.begin(operationID: "op-3"), "gate returns to idle after cancel")
}

// Cleaner history: persistence round-trip and aggregates.
do {
    let historyRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("3106-history-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: historyRoot, withIntermediateDirectories: true)
    CleanerHistory.setRootForTesting(historyRoot)
    defer {
        CleanerHistory.clear()
        CleanerHistory.setRootForTesting(nil)
        try? FileManager.default.removeItem(at: historyRoot)
    }
    CleanerHistory.clear()
    let empty = CleanerHistory.loadEntries()
    expect(empty.isEmpty, "history starts empty after clear")

    CleanerHistory.record(CleanerHistoryEntry(
        cleanedAppCount: 3, failedItemCount: 0, freedBytes: 1024
    ))
    CleanerHistory.record(CleanerHistoryEntry(
        cleanedAppCount: 1, failedItemCount: 2, freedBytes: 2048,
        crashLogsRemoved: 5, crashLogBytes: 512
    ))
    let entries = CleanerHistory.loadEntries()
    expect(entries.count == 2, "history persists both entries")
    expect(entries[0].freedBytes == 2048, "history is newest-first")
    expect(entries[0].totalFreedBytes == 2048 + 512, "crash-log bytes aggregate into totals")
    expect(CleanerHistory.totalFreedBytes(in: entries) == 1024 + 2048 + 512,
           "total freed bytes sums all entries")
    expect(CleanerHistory.totalCleanedApps(in: entries) == 4,
           "total cleaned apps sums all entries")

    CleanerHistory.clear()
    expect(CleanerHistory.loadEntries().isEmpty, "clear empties history")
}

// Activity history: persistence round-trip, ordering and cap.
do {
    let activityRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("3106-activity-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: activityRoot, withIntermediateDirectories: true)
    ActivityHistory.setRootForTesting(activityRoot)
    defer {
        ActivityHistory.clear()
        ActivityHistory.setRootForTesting(nil)
        try? FileManager.default.removeItem(at: activityRoot)
    }
    ActivityHistory.clear()
    expect(ActivityHistory.load().isEmpty, "activity starts empty after clear")

    ActivityHistory.log(.backup, feature: "savebackup", "com.a")
    ActivityHistory.log(.restore, feature: "savebackup", "com.a")
    ActivityHistory.log(.clean, feature: "cleaner", "apps=3 freed=1024")
    ActivityHistory.log(.write, feature: "gestalt", "preset:aod")

    let events = ActivityHistory.load()
    expect(events.count == 4, "activity persists all four events")
    expect(events[0].kind == .write, "activity is newest-first")
    expect(events.map(\.kind) == [.write, .clean, .restore, .backup],
           "activity kinds ordered newest-first")

    // The 300-entry cap keeps the newest slice.
    for index in 0..<310 {
        ActivityHistory.log(.write, feature: "stress", "entry-\(index)")
    }
    expect(ActivityHistory.load().count == 300, "activity caps at 300 entries")

    ActivityHistory.clear()
    expect(ActivityHistory.load().isEmpty, "clear empties activity")
}

// ── v3.2.1 verification block ──────────────────────────────────────────
// Real-logic verification for this release: AltStore adapter (real
// AltGallery manifest shape), update-check version comparison, the
// open-ended-range compatibility fix, and the 27.3 / 26.5 policy flips.
// These run in the bare CLI harness — no UIKit, no sandbox grants.

// 1) AltStoreSourceAdapter: a realistic AltGallery-shaped manifest.
do {
    let manifestJSON = """
    {
      "name": "AltGallery",
      "subtitle": "aggregate",
      "iconURL": "https://raw.githubusercontent.com/bebound/AltGallery/master/icon.png",
      "apps": [
        {
          "name": "Aidoku",
          "bundleIdentifier": "app.aidoku.Aidoku",
          "developerName": "Aidoku",
          "subtitle": "Manga reader",
          "localizedDescription": "An open source manga reader.",
          "iconURL": "https://raw.githubusercontent.com/bebound/AltGallery/master/aidoku.png",
          "versions": [
            {
              "version": "0.9.1",
              "date": "2026-10-01T00:00:00Z",
              "localizedDescription": "bugfixes",
              "downloadURL": "https://github.com/Aidoku/Aidoku/releases/download/v0.9-4/Aidoku.ipa",
              "size": 14753154,
              "minOSVersion": "15.0"
            }
          ]
        },
        {
          "name": "Duplicate Bundle",
          "bundleIdentifier": "app.aidoku.Aidoku",
          "versions": [
            {"version": "0.1", "downloadURL": "https://github.com/x/x/releases/download/v1/x.ipa"}
          ]
        },
        {
          "name": "Bad Link",
          "bundleIdentifier": "com.bad.link",
          "versions": [
            {"version": "1.0", "downloadURL": "http://insecure.example.com/x.ipa"}
          ]
        }
      ]
    }
    """
    let data = Data(manifestJSON.utf8)
    let repo = try AltStoreSourceAdapter.decode(
        data,
        sourceURL: URL(string: "https://raw.githubusercontent.com/bebound/AltGallery/refs/heads/master/all-apps.json")!
    )
    expect(repo.identifier == "altgallery", "adapter: repo identifier")
    expect(repo.packages.count == 1, "adapter: duplicate bundle deduped, insecure link skipped (3 apps -> 1)")
    let pkg = repo.packages[0]
    expect(pkg.identifier == "app.aidoku.Aidoku", "adapter: bundle id becomes package identifier")
    expect(pkg.kind == .ipa, "adapter: kind is .ipa")
    expect(pkg.version == "0.9.1", "adapter: newest version picked")
    expect(pkg.expectedSize == 14_753_154, "adapter: size carried through")
    expect(pkg.supportedOS.count == 1 && pkg.supportedOS[0].maximum == "99.0.0",
           "adapter: open range expressed via sentinel maximum")
    expect(pkg.downloadURL.scheme == "https", "adapter: download URL https")

    // Compatibility: 3.2.1 device must see the package as compatible
    // (regression for the nil-maximum bug that greyed every install).
    let compatibility = PackageCompatibilityEvaluator.evaluate(
        pkg.supportedOS, major: 27, minor: 0, patch: 1, build: "any"
    )
    expect(compatibility == .compatible, "adapter: open range evaluates compatible on 27.0.1")

    // Oversized manifest refused.
    let huge = Data(repeating: 65, count: PackageRepositoryLimits.maximumManifestBytes + 1)
    var threw = false
    _ = try? AltStoreSourceAdapter.decode(huge, sourceURL: repo.sourceURL)
    do {
        _ = try AltStoreSourceAdapter.decode(huge, sourceURL: repo.sourceURL)
    } catch {
        threw = true
    }
    expect(threw, "adapter: oversized manifest refused")
}

// 2) AppUpdateChecker version comparison (3.2.1 release gate).
do {
    expect(AppVersionComparison.isNewer("v3.2.1", than: "3.2.0"), "update: v-prefixed newer tag detected")
    expectFalse(AppVersionComparison.isNewer("v3.2.1", than: "3.2.1"), "update: same version not newer")
    expectFalse(AppVersionComparison.isNewer("3.2.0", than: "3.2.1"), "update: older tag not newer")
    expect(AppVersionComparison.isNewer("3.2.10", than: "3.2.9"), "update: numeric not lexicographic (10 > 9)")
    expect(AppVersionComparison.normalize(" v3.2.1 ") == "3.2.1", "update: normalize strips v and whitespace")
    expect(AppVersionComparison.isNewer("v4", than: "3.2.1"), "update: major bump detected")
}

// 3) Support policy flips (27.3 build-gated, 26.5 layouts unchanged).
do {
    expect(ExploitSupportPolicy.supportsWorseQuery(major: 27, minor: 3, patch: 0, build: "24C5037i"),
           "policy: 27.3 beta 1 verified & supported")
    expectFalse(ExploitSupportPolicy.supportsWorseQuery(major: 27, minor: 3, patch: 0, build: "24C5049d"),
                "policy: 27.3 beta 2 blocked after Apple patch")
    expectFalse(ExploitSupportPolicy.isSupported(major: 27, minor: 3, patch: 0, build: "24C5049d"),
                "policy: 27.3 beta 2 not supported, no experimental fallback")
    expectFalse(ExploitSupportPolicy.supportsWorseQuery(major: 26, minor: 7, patch: 3),
                "policy: 26.7.3 beyond worse_query ceiling")
    expect(ExploitSupportPolicy.supportsBadQuery(major: 26, minor: 6, patch: 1),
           "policy: 26.6.1 still bad_query")
    expectFalse(ExploitSupportPolicy.supportsBadQuery(major: 26, minor: 6, patch: 2),
                "policy: 26.6.2 past bad_query")
}

// 4) Version parsing edge used by PackageSystemVersion (sentinel path).
do {
    let maxRange = PackageOSRange(minimum: "15.0", maximum: "99.0.0", builds: nil)
    expect(PackageCompatibilityEvaluator.evaluate(
        [maxRange], major: 26, minor: 5, patch: 0, build: "b"
    ) == .compatible, "compat: sentinel maximum covers 26.5")
    expect(PackageCompatibilityEvaluator.evaluate(
        [maxRange], major: 14, minor: 0, patch: 0, build: "b"
    ) == .incompatible, "compat: below minimum (14.0 < 15.0) refused")
}

// MARK: - AppUpdateChecker version comparison (3.2.4 regression guard)

do {
    // normalize strips the leading v.
    expect(AppUpdateChecker.normalize("v3.2.4") == "3.2.4", "normalize strips v prefix")
    expect(AppUpdateChecker.normalize(" 3.2.4 ") == "3.2.4", "normalize trims whitespace")

    // isNewer: strict semver-ish numeric comparison, equal = false.
    expect(AppUpdateChecker.isNewer("3.2.4", than: "3.2.3"), "3.2.4 newer than 3.2.3")
    expect(AppUpdateChecker.isNewer("v3.3.0", than: "3.2.3"), "v-prefixed remote compares numerically")
    expectFalse(AppUpdateChecker.isNewer("3.2.3", than: "3.2.3"), "same version is not newer")
    expectFalse(AppUpdateChecker.isNewer("3.2.2", than: "3.2.3"), "older remote refused")
    expect(AppUpdateChecker.isNewer("3.3", than: "3.2.9"), "missing patch treated as 0 (3.3.0 > 3.2.9)")
    expect(AppUpdateChecker.isNewer("3.10.0", than: "3.9.9"), "numeric not lexicographic (10 > 9)")
    expectFalse(AppUpdateChecker.isNewer("3.2.3-beta", than: "3.2.3"), "prerelease suffix does not outrank release")

    // FailureReason classification keys exist for each case (string keys
    // keep the UI test surface stable).
    expect(AppUpdateChecker.FailureReason.offline.localizationKey == "update.failure.offline",
           "offline reason maps to its key")
    expect(AppUpdateChecker.FailureReason.httpStatus(403).localizationKey == "update.failure.http",
           "http-status reason maps to its key")
}

// MARK: - TaskCancellation (stage 1, WCF-1)

do {
    let token = CancellationToken()
    expectFalse(token.isCancelled, "cancellation token starts live")

    var fired = 0
    token.onCancel { fired += 1 }
    token.cancel(reason: "test")
    expect(token.isCancelled, "cancel flips the flag")
    expect(token.cancelReason == "test", "cancel captures the reason")
    expect(fired == 1, "registered handler fired once on cancel")

    // Cancel is idempotent: a second call must not re-fire handlers.
    token.cancel(reason: "second")
    expect(fired == 1, "second cancel does not re-fire handlers")

    // Late registration on a cancelled token fires immediately.
    var late = 0
    token.onCancel { late += 1 }
    expect(late == 1, "handler registered after cancel fires immediately")

    // check() throws CancellationError after cancel.
    do {
        try token.check()
        expectFalse(true, "check() should throw after cancel")
    } catch {
        expect(error is CancellationError, "check() throws CancellationError")
    }

    // A live token's check() is a no-op.
    let live = CancellationToken()
    try? live.check()
    expectFalse(live.isCancelled, "check() on live token does not cancel it")
}

// MARK: - TempSpaceRegistry lease expiry (stage 1, G7)

do {
    let now = Date()
    let session = TempSpaceRegistry.Lease(id: UUID(), path: "/tmp/x-session",
                                          purpose: "t", createdAt: now.addingTimeInterval(-5 * 3600),
                                          retention: .session)
    expectFalse(session.isExpired(now: now), "session lease of 5h still valid (limit 6h)")

    let staleSession = TempSpaceRegistry.Lease(id: UUID(), path: "/tmp/x-session2",
                                               purpose: "t", createdAt: now.addingTimeInterval(-7 * 3600),
                                               retention: .session)
    expect(staleSession.isExpired(now: now), "session lease of 7h expired")

    let hours24 = TempSpaceRegistry.Lease(id: UUID(), path: "/tmp/x-24",
                                          purpose: "t", createdAt: now.addingTimeInterval(-23 * 3600),
                                          retention: .hours24)
    expectFalse(hours24.isExpired(now: now), "24h lease of 23h still valid")

    let days7 = TempSpaceRegistry.Lease(id: UUID(), path: "/tmp/x-7d",
                                        purpose: "t", createdAt: now.addingTimeInterval(-6.5 * 24 * 3600),
                                        retention: .days7)
    expectFalse(days7.isExpired(now: now), "7d lease of 6.5d still valid")

    let expiredDays7 = TempSpaceRegistry.Lease(id: UUID(), path: "/tmp/x-7d2",
                                               purpose: "t", createdAt: now.addingTimeInterval(-8 * 24 * 3600),
                                               retention: .days7)
    expect(expiredDays7.isExpired(now: now), "7d lease of 8d expired")
}

// MARK: - TextPagination (stage 1, W4)

do {
    expect(TextPagination.paginate("").isEmpty, "empty text yields no pages")

    let one = TextPagination.paginate("a")
    expect(one.count == 1 && one[0] == "a", "single char yields one page")

    let exact = String(repeating: "x", count: 6_000)
    expect(TextPagination.paginate(exact).count == 1, "exactly one page yields one page")

    let over = String(repeating: "y", count: 6_001)
    let overPages = TextPagination.paginate(over)
    expect(overPages.count == 2, "6001 chars spill to a second page")
    expect(overPages[1] == "y", "spill page carries the remainder")

    // Content fidelity: rejoining pages must reproduce the input.
    let long = String((0..<15_000).map { Character(UnicodeScalar(65 + $0 % 26)!) })
    let longPages = TextPagination.paginate(long)
    expect(longPages.count == 3, "15000 chars split into 3 pages")
    expect(longPages.joined() == long, "pagination preserves content exactly")

    // Custom limit respected.
    let small = TextPagination.paginate("abcdef", pageLimit: 2)
    expect(small == ["ab", "cd", "ef"], "custom pageLimit respected")
}

// MARK: - Issue #3: cleaner policy vs the /var -> /private/var symlink

// On iOS (and macOS) /var is a symlink to /private/var. The cleaner's
// component walk lstat()s every ancestor; before the fix the /var component
// resolved to /private/var and was then compared against an uncanonicalized
// container root, so EVERY clean was rejected as symlinkEscapesContainer.
do {
    // Build a real container on disk with a real in-container symlink
    // (Library/Caches -> tmp-cache), mirroring what apps ship.
    let base = NSTemporaryDirectory()
    let root = URL(fileURLWithPath: base)
        .appendingPathComponent("3106-cleaner-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
        at: root.appendingPathComponent("Library/Caches", isDirectory: true),
        withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
        at: root.appendingPathComponent("tmp-cache", isDirectory: true),
        withIntermediateDirectories: true
    )
    // Replace Library/Caches with a symlink pointing at tmp-cache INSIDE the
    // container (the common app layout the policy explicitly allows).
    try FileManager.default.removeItem(at: root.appendingPathComponent("Library/Caches"))
    try FileManager.default.createSymbolicLink(
        at: root.appendingPathComponent("Library/Caches", isDirectory: true),
        withDestinationURL: root.appendingPathComponent("tmp-cache")
    )
    try FileManager.default.createDirectory(
        at: root.appendingPathComponent("tmp", isDirectory: true),
        withIntermediateDirectories: true
    )

    // Exercise the policy through the /var spelling so the walk hits the
    // system-level symlink exactly like on a device.
    let rootVarSpelling = root.path.replacingOccurrences(
        of: "/private/var",
        with: "/var"
    )
    let cachesTarget = CleanerSafetyPolicy.PlannedTarget.build(
        containerRoot: rootVarSpelling,
        relativePath: "Library/Caches"
    )
    let tmpTarget = CleanerSafetyPolicy.PlannedTarget.build(
        containerRoot: rootVarSpelling,
        relativePath: "tmp"
    )
    expect(cachesTarget != nil, "PlannedTarget.build accepts a /var-spelled root")
    expect(tmpTarget != nil, "PlannedTarget.build accepts /var root for tmp")

    if let cachesTarget {
        expect(
            CleanerSafetyPolicy.checkTarget(cachesTarget, snapshot: nil) == .allowed,
            "in-container Caches symlink allowed through /var root (issue #3)"
        )
    }
    if let tmpTarget {
        expect(
            CleanerSafetyPolicy.checkTarget(tmpTarget, snapshot: nil) == .allowed,
            "plain tmp allowed through /var root (issue #3)"
        )
    }

    // Escape must still be rejected: point the Caches symlink OUTSIDE the
    // container and re-check.
    let escapeLink = root.appendingPathComponent("Library/Caches")
    try FileManager.default.removeItem(at: escapeLink)
    try FileManager.default.createSymbolicLink(
        at: escapeLink,
        withDestinationURL: URL(fileURLWithPath: "/tmp")
    )
    if let cachesTarget {
        expect(
            CleanerSafetyPolicy.checkTarget(cachesTarget, snapshot: nil)
                == .rejected(reason: .symlinkEscapesContainer),
            "escape symlink outside the container still rejected"
        )
    }
    // A sibling-prefix root must not satisfy containment.
    expectFalse(
        LaunchServicesStore.isPath(
            root.path + "X/Library/Caches",
            containedIn: root.path
        ),
        "cleaner containment rejects a sibling prefix"
    )

    try? FileManager.default.removeItem(at: root)
}

// MARK: - Issue #3: descriptor-skip diagnosis fields

do {
    // validExtensionIdentifier must accept the real Apple extension id that
    // appeared in the skipped-descriptor log (issue #3).
    expect(
        WallpaperLayoutScanner.validExtensionIdentifier(
            "com.apple.WallpaperKit.CollectionsPoster"
        ),
        "CollectionsPoster identifier passes the extension check"
    )
    // And the container-identity variant used elsewhere keeps passing.
    expect(
        !WallpaperLayoutScanner.validExtensionIdentifier("no-dot"),
        "identifier without a dot rejected"
    )
}

// MARK: - GestaltX v1.1.1 #131/#132/#138 field-import integrity

do {
    let current: [String: Any] = [
        "CacheUUID": "ABCD-1234",
        "CacheVersion": NSNumber(value: 7),
        "CacheData": Data([1, 2, 3]),
        "PrivateLayout": "device-specific",
        "CacheExtra": [
            "keep": "original",
            "edit": NSNumber(value: false),
            "camera": NSNumber(value: 1.5),
        ],
    ]
    let imported: [String: Any] = [
        "CacheUUID": "abcd-1234",
        "CacheVersion": NSNumber(value: 99),
        "CacheData": Data([9, 9, 9]),
        "PrivateLayout": "foreign",
        "CacheExtra": [
            "edit": NSNumber(value: true),
            "unknown": "must-not-be-added",
        ],
    ]
    let result = try GestaltPlistMerge.mergingFieldImport(
        current: current, imported: imported
    )
    let extra = result.root["CacheExtra"] as? [String: Any] ?? [:]
    expect((result.root["CacheVersion"] as? NSNumber)?.intValue == 7,
           "field import preserves current CacheVersion")
    expect((result.root["CacheData"] as? Data) == Data([1, 2, 3]),
           "field import preserves device-specific CacheData")
    expect((result.root["PrivateLayout"] as? String) == "device-specific",
           "field import preserves private root keys")
    expect((extra["keep"] as? String) == "original",
           "field import does not remove current CacheExtra keys")
    expect((extra["edit"] as? NSNumber)?.boolValue == true,
           "field import overwrites explicit CacheExtra keys")
    expect(extra["unknown"] == nil,
           "field import skips keys absent from the device cache")
    expect(result.overwritten == ["edit"], "field import reports overwritten keys")
    expect(result.skipped == ["unknown"], "field import reports skipped keys")
    expect(CFGetTypeID(extra["edit"] as! NSNumber) == CFBooleanGetTypeID(),
           "field import keeps Boolean CF type")
    expect((extra["camera"] as? NSNumber)?.doubleValue == 1.5,
           "field import keeps untouched Real value")

    let mismatched = try? GestaltPlistMerge.mergingFieldImport(
        current: current,
        imported: ["CacheUUID": "DIFFERENT", "CacheExtra": ["edit": "x"]]
    )
    expect(mismatched == nil, "different CacheUUID rejects field import")
    let missing = try? GestaltPlistMerge.mergingFieldImport(
        current: ["CacheExtra": ["a": "b"]], imported: ["Other": "value"]
    )
    expect(missing == nil, "missing CacheExtra rejects field import")

    expect(IdentityComparator.caseInsensitiveEqual(" ABCD-1234 ", "abcd-1234"),
           "cache UUID comparison ignores case and surrounding whitespace")
    expectFalse(IdentityComparator.caseInsensitiveEqual("ABCD-1234", "ABCD-5678"),
                "cache UUID comparison still rejects different UUIDs")

    expect(GestaltValueParser.parseDate("2026-11-14T08:30:00Z") != nil,
           "strict date parser accepts ISO8601")
    expect(GestaltValueParser.parseDate("2026-11-14T08:30:00.123Z") != nil,
           "strict date parser accepts fractional seconds")
    expect(GestaltValueParser.parseDate("2026-11-14T08:30:00Zjunk") == nil,
           "strict date parser rejects trailing text (#132)")
    expect(GestaltValueParser.parseData("AQID") == Data([1, 2, 3]),
           "strict data parser accepts base64")
    expect(GestaltValueParser.parseData("AQIDjunk!") == nil,
           "strict data parser rejects malformed base64")
    expect(GestaltValueParser.parseData("   ") == nil,
           "strict data parser rejects empty input")
}

// MARK: - GestaltX v1.1.1 #134 backup metadata validation

do {
    let archive = "com.example.app-123.3106save"
    let sidecar = BackupMetadataPolicy.sidecarName(forArchive: archive)
    expect(sidecar == "com.example.app-123.manifest.plist",
           "backup sidecar name is derived from the archive name")
    expect(BackupMetadataPolicy.validateSidecarName(
        archiveName: archive, sidecarName: sidecar
    ) == .valid, "valid backup sidecar name accepted")
    expect(BackupMetadataPolicy.validateSidecarName(
        archiveName: archive, sidecarName: "other.manifest.plist"
    ) == .rejected(reason: .invalidSidecarName),
           "mismatched backup sidecar name rejected")
    expect(BackupMetadataPolicy.validateSidecarName(
        archiveName: "com.example.app-123.zip", sidecarName: sidecar
    ) == .rejected(reason: .invalidSidecarName),
           "non-3106save archive rejected")

    let now = Date()
    expect(BackupMetadataPolicy.validateManifest(
        bundleID: "com.example.app", createdAt: now.addingTimeInterval(-60), now: now
    ) == .valid, "valid backup manifest accepted")
    expect(BackupMetadataPolicy.validateManifest(
        bundleID: "", createdAt: now, now: now
    ) == .rejected(reason: .emptyBundleID), "empty bundle ID rejected")
    expect(BackupMetadataPolicy.validateManifest(
        bundleID: "example", createdAt: now, now: now
    ) == .rejected(reason: .invalidBundleID), "single-component bundle ID rejected")
    expect(BackupMetadataPolicy.validateManifest(
        bundleID: "com.example/app", createdAt: now, now: now
    ) == .rejected(reason: .invalidBundleID), "bundle ID with slash rejected")
    expect(BackupMetadataPolicy.validateManifest(
        bundleID: "com.example.app", createdAt: now.addingTimeInterval(3600), now: now
    ) == .rejected(reason: .futureTimestamp), "future createdAt rejected")

    expect(BackupMetadataPolicy.validateArchivePath("Library/Preferences/a.plist") == .valid,
           "safe archive path accepted")
    expect(BackupMetadataPolicy.validateArchivePath("../escape.plist") ==
           .rejected(reason: .unsafePath), "parent traversal rejected")
    expect(BackupMetadataPolicy.validateArchivePath("/absolute.plist") ==
           .rejected(reason: .unsafePath), "absolute archive path rejected")
    expect(BackupMetadataPolicy.validateArchivePath("Library\\escape.plist") ==
           .rejected(reason: .unsafePath), "backslash archive path rejected")
    expect(BackupMetadataPolicy.validateArchivePath("Library/./a.plist") ==
           .rejected(reason: .unsafePath), "dot component rejected")
    expect(BackupMetadataPolicy.validateManifest(
        bundleID: "com.example.app",
        createdAt: now.addingTimeInterval(BackupMetadataPolicy.maxFutureTolerance - 1),
        now: now
    ) == .valid, "small clock drift within tolerance accepted")
    expect(BackupMetadataPolicy.validateManifest(
        bundleID: "com.example.app",
        createdAt: now.addingTimeInterval(BackupMetadataPolicy.maxFutureTolerance + 1),
        now: now
    ) == .rejected(reason: .futureTimestamp), "clock drift beyond tolerance rejected")
}

// MARK: - GestaltX v1.1.1 #136/#137/#139 edit precedence and exact plist types

do {
    let snapshot = [
        GestaltEditPolicy.Field(key: "camera", preview: "1.5"),
        GestaltEditPolicy.Field(key: "region", preview: "US"),
    ]
    expect(GestaltEditPolicy.filtered(snapshot, query: "1.5").map(\.key) == ["camera"],
           "field search matches snapshot preview once")
    expect(GestaltEditPolicy.filtered(snapshot, query: " ").count == 2,
           "blank field search returns the whole snapshot")
    expect(GestaltEditPolicy.filtered(snapshot, query: "REGION").map(\.key) == ["region"],
           "field search is case-insensitive")

    expect(GestaltEditPolicy.keysToApply(
        presetKeys: ["a", "b", "c"], explicitEdits: ["b"]
    ) == ["a", "c"], "explicit field edits win over layout presets")
    expect(GestaltEditPolicy.keysToApply(
        presetKeys: ["a"], explicitEdits: ["a"]
    ).isEmpty, "fully explicit preset has no keys to write")

    expect(GestaltEditPolicy.exactlyEqual(NSNumber(value: true), NSNumber(value: true)),
           "Boolean exact comparison accepts equal values")
    expectFalse(GestaltEditPolicy.exactlyEqual(NSNumber(value: true), NSNumber(value: 1)),
                "Boolean never equals Integer 1")
    expectFalse(GestaltEditPolicy.exactlyEqual(NSNumber(value: 1), NSNumber(value: 1.0)),
                "Integer never equals Real 1.0")
    expect(GestaltEditPolicy.exactlyEqual(
        ["a": NSNumber(value: true), "b": Data([1, 2])] as [String: Any],
        ["b": Data([1, 2]), "a": NSNumber(value: true)] as [String: Any]
    ), "nested dictionary exact comparison is order-independent")
    expectFalse(GestaltEditPolicy.exactlyEqual(
        ["a": NSNumber(value: true)] as [String: Any],
        ["a": NSNumber(value: 1)] as [String: Any]
    ), "nested dictionary compares CF types")

    let disabledBoolean = GestaltEditPolicy.disabledValue(for: NSNumber(value: true))
    expect(CFGetTypeID(disabledBoolean as! NSNumber) == CFBooleanGetTypeID(),
           "disabled Boolean keeps Boolean CF type")
    let disabledInteger = GestaltEditPolicy.disabledValue(for: NSNumber(value: 7))
    expect(CFGetTypeID(disabledInteger as! NSNumber) != CFBooleanGetTypeID(),
           "disabled Integer keeps numeric CF type")
    expect((disabledInteger as? NSNumber)?.intValue == 0,
           "disabled Integer writes zero instead of deleting the key")
    let disabledReal = GestaltEditPolicy.disabledValue(for: NSNumber(value: 2.5))
    expect(CFNumberIsFloatType(unsafeBitCast(disabledReal as! NSNumber, to: CFNumber.self)),
           "disabled Real keeps Real CF type")
}

// MARK: - GestaltX App Audio Library parity: notification sound policy

do {
    expect(NotificationSoundPolicy.acceptsSourceExtension("CAF"),
           "notification sound accepts caf case-insensitively")
    expect(NotificationSoundPolicy.acceptsSourceExtension("m4a"),
           "notification sound accepts m4a")
    expectFalse(NotificationSoundPolicy.acceptsSourceExtension("tone.mp3"),
                "notification sound rejects mp3")
    expectFalse(NotificationSoundPolicy.acceptsSourceExtension("tone"),
                "notification sound rejects missing extension")

    expectThrows("notification sound rejects empty source", expected: .emptySource) {
        try NotificationSoundPolicy.validateSourceSize(0)
    }
    expectThrows("notification sound rejects oversized source", expected: .tooLarge) {
        try NotificationSoundPolicy.validateSourceSize(
            NotificationSoundPolicy.maximumBytes + 1
        )
    }
    expectNoThrow("notification sound accepts source at the size limit") {
        try NotificationSoundPolicy.validateSourceSize(
            NotificationSoundPolicy.maximumBytes
        )
    }

    let root = NSTemporaryDirectory() + "3106-ns-verify-\(UUID().uuidString)"
    let container = root + "/var/containers/app-data"
    try FileManager.default.createDirectory(
        atPath: container + "/Library/Sounds", withIntermediateDirectories: true
    )
    let sound = container + "/Library/Sounds/local.caf"
    try Data([1, 2, 3]).write(to: URL(fileURLWithPath: sound))

    expectNoThrow("notification sound accepts an in-container target") {
        try NotificationSoundPolicy.validateTargetPath(
            sound, containerRoot: container
        )
    }
    expectThrows("notification sound rejects parent traversal", expected: .unsafePath) {
        try NotificationSoundPolicy.validateTargetPath(
            container + "/../../../escape.caf", containerRoot: container
        )
    }
    expectThrows("notification sound rejects absolute targets", expected: .unsafePath) {
        try NotificationSoundPolicy.validateTargetPath(
            "/Library/Sounds/local.caf", containerRoot: container
        )
    }
    expectThrows("notification sound rejects backslash paths", expected: .unsafePath) {
        try NotificationSoundPolicy.validateTargetPath(
            container + "/Library\\Sounds/local.caf", containerRoot: container
        )
    }
    expectThrows("notification sound rejects missing targets", expected: .targetMissing) {
        try NotificationSoundPolicy.validateTargetPath(
            container + "/Library/Sounds/missing.caf", containerRoot: container
        )
    }
    try? FileManager.default.removeItem(at: URL(fileURLWithPath: root))
}

// ── GrantRetry: permission classification + retry primitive (T-007) ──

do {
    // errno extraction across the shapes the write paths produce.
    expect(GrantRetry.errno(of: POSIXError(POSIXErrorCode.EPERM)) == EPERM, "POSIXError EPERM recognized")
    expect(
        GrantRetry.errno(of: NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))) == EACCES,
        "NSError POSIX-domain EACCES recognized"
    )
    expect(
        GrantRetry.errno(of: NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)) == EACCES,
        "CocoaError 513 folds to EACCES"
    )
    expect(
        GrantRetry.errno(of: NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)) == EACCES,
        "CocoaError 257 folds to EACCES"
    )
    expect(
        GrantRetry.errno(of: BackupError.writeFailed("open /var/x errno 1")) == EPERM,
        "BackupError.writeFailed embedded errno parsed"
    )
    expect(
        GrantRetry.errno(of: BackupError.writeFailed("write errno 13")) == EACCES,
        "BackupError.writeFailed write errno parsed"
    )
    expect(
        GrantRetry.errno(of: BackupError.writeFailed("target changed while opening /x")) == 0,
        "writeFailed without errno maps to 0"
    )
    expectFalse(
        GrantRetry.isPermissionDenied(BackupError.targetMissing("/x")),
        "targetMissing is not a permission denial"
    )
    expectFalse(
        GrantRetry.isPermissionDenied(BackupError.writeFailed("target changed while opening /x")),
        "writeFailed without errno is not a permission denial"
    )

    // Failure-code → localization key mapping (single source of truth for
    // GrantFailure.errorDescription and the diagnostics export).
    expect(GrantRetry.failureKey(for: -1) == "sandbox.error.no_app_group", "code -1 mapped")
    expect(GrantRetry.failureKey(for: -4) == "sandbox.error.swap_failed", "code -4 mapped")
    expect(GrantRetry.failureKey(for: -8) == "sandbox.error.token_unopenable", "code -8 mapped")
    expect(GrantRetry.failureKey(for: -254) == "sandbox.error.lstat_denied", "code -254 mapped")
    expect(GrantRetry.failureKey(for: -999) == "sandbox.error.unknown", "unknown code mapped")

    // Retry primitive with spy grant/invalidate closures.
    var grantCalls = 0
    var invalidateCalls = 0
    let grant: (String) -> Int64 = { _ in grantCalls += 1; return 42 }
    let invalidate: () -> Void = { invalidateCalls += 1 }

    var bodyCalls = 0
    let ok = try GrantRetry.withRetry(
        directory: "/tmp/x", backend: "worse_query", grant: grant, invalidate: invalidate
    ) {
        bodyCalls += 1
        return "done"
    }
    expect(ok == "done", "retry: first-attempt success returns the body result")
    expect(
        grantCalls == 1 && invalidateCalls == 0 && bodyCalls == 1,
        "retry: success path grants once, never invalidates, runs body once"
    )

    grantCalls = 0
    invalidateCalls = 0
    var attempts = 0
    let healed = try GrantRetry.withRetry(
        directory: "/tmp/x", backend: "worse_query", grant: grant, invalidate: invalidate
    ) {
        attempts += 1
        if attempts == 1 { throw POSIXError(POSIXErrorCode.EPERM) }
        return "healed"
    }
    expect(healed == "healed", "retry: EPERM then success heals")
    expect(
        grantCalls == 2 && invalidateCalls == 1 && attempts == 2,
        "retry: heals with exactly one re-grant cycle and one retry"
    )

    grantCalls = 0
    invalidateCalls = 0
    struct UnrelatedError: Error {}
    do {
        _ = try GrantRetry.withRetry(
            directory: "/tmp/x", backend: "worse_query", grant: grant, invalidate: invalidate
        ) {
            throw UnrelatedError()
        }
        expect(false, "retry: non-permission error must propagate")
    } catch {
        expect(error is UnrelatedError, "retry: non-permission error propagates untranslated")
        expect(grantCalls == 1 && invalidateCalls == 0, "retry: non-permission error does not invalidate")
    }

    grantCalls = 0
    invalidateCalls = 0
    do {
        _ = try GrantRetry.withRetry(
            directory: "/tmp/x", backend: "worse_query", grant: grant, invalidate: invalidate
        ) {
            throw POSIXError(POSIXErrorCode.EPERM)
        }
        expect(false, "retry: double EPERM must throw GrantFailure")
    } catch let failure as GrantFailure {
        if case .writeDenied(let errno, let path, let grantCode) = failure {
            expect(errno == EPERM, "writeDenied carries the retried errno")
            expect(path == "/tmp/x", "writeDenied carries the directory")
            expect(grantCode == 42, "writeDenied carries the retry grant handle")
        } else {
            expect(false, "retry: expected writeDenied, got \(failure)")
        }
        expect(
            grantCalls == 2 && invalidateCalls == 1,
            "retry: double failure runs exactly one re-grant cycle"
        )
    } catch {
        expect(false, "retry: double EPERM threw an unexpected error type")
    }

    grantCalls = 0
    invalidateCalls = 0
    var bodyRan = false
    let denyGrant: (String) -> Int64 = { _ in grantCalls += 1; return -8 }
    do {
        _ = try GrantRetry.withRetry(
            directory: "/tmp/x", backend: "worse_query", grant: denyGrant, invalidate: invalidate
        ) {
            bodyRan = true
            return "x"
        }
        expect(false, "retry: negative grant must throw GrantFailure.denied")
    } catch let failure as GrantFailure {
        if case .denied(let code, _, let backend) = failure {
            expect(code == -8, "denied carries the failing grant code")
            expect(backend == "worse_query", "denied carries the backend name")
        } else {
            expect(false, "retry: expected denied, got \(failure)")
        }
        expect(grantCalls == 1 && invalidateCalls == 0, "denied: no invalidate on fast fail")
    } catch {
        expect(false, "retry: negative grant threw an unexpected error type")
    }
    expectFalse(bodyRan, "denied: the body never runs")

    var grantSequence: [Int64] = [42, -1]
    let seqGrant: (String) -> Int64 = { _ in grantSequence.removeFirst() }
    do {
        _ = try GrantRetry.withRetry(
            directory: "/tmp/x", backend: "worse_query", grant: seqGrant, invalidate: {}
        ) {
            throw POSIXError(POSIXErrorCode.EACCES)
        }
        expect(false, "retry: negative retry grant must throw")
    } catch let failure as GrantFailure {
        if case .denied(let code, _, _) = failure {
            expect(code == -1, "retry-denied carries the retry grant code")
        } else {
            expect(false, "retry: expected denied on negative retry grant, got \(failure)")
        }
    } catch {
        expect(false, "retry: negative retry grant threw an unexpected error type")
    }
}

// ── LaunchServicesStore: synthetic 27.2/27.3 fixtures (T-008, F-07) ──
// Builds a minimal binary store with one bundle record and the string-table
// entries it references, then asserts the winning layout label per OS
// family. Record format (from LaunchServicesStore): 8-byte header with the
// record size at +4, body fields at layout offsets; string entries are
// `u32 id + u32 length + bytes` 4-byte aligned; refs are stringID << 2.
do {
    func le32(_ value: UInt32) -> [UInt8] {
        [UInt8(value & 0xff), UInt8((value >> 8) & 0xff),
         UInt8((value >> 16) & 0xff), UInt8((value >> 24) & 0xff)]
    }

    // String entry: u32 id, u32 byte length, payload, zero padding to 4.
    func stringEntry(id: UInt32, _ text: String) -> [UInt8] {
        var entry = le32(id) + le32(UInt32(text.utf8.count)) + Array(text.utf8)
        while entry.count % 4 != 0 { entry.append(0) }
        return entry
    }

    // One bundle record for a given layout: header (size at +4) + refs at
    // the layout's body offsets. Unused fields stay 0 — the parser only
    // requires a valid bundle-id ref.
    func bundleRecord(bundleSize: UInt32, bundleID: Int, name: Int,
                      displayName: Int, container: Int,
                      refs: (bundleID: UInt32, name: UInt32,
                             displayName: UInt32, container: UInt32)) -> [UInt8] {
        var body = [UInt8](repeating: 0, count: Int(bundleSize))
        func put(_ value: UInt32, at offset: Int) {
            let bytes = le32(value)
            for (index, byte) in bytes.enumerated() { body[offset + index] = byte }
        }
        put(refs.bundleID, at: bundleID)
        put(refs.name, at: name)
        put(refs.displayName, at: displayName)
        put(refs.container, at: container)
        return le32(0) + le32(bundleSize) + body
    }

    let bundleIDText = "com.example.fixture"
    // isDataContainerPath requires exactly prefix + 36 chars and a
    // UUID-parseable tail — use the canonical dashed form.
    let realContainer = "/private/var/mobile/Containers/Data/Application/"
        + "01234567-89AB-CDEF-0123-456789ABCDEF" // 36-char UUID

    // String IDs: 1 = bundle id, 2 = container path. refs = id << 2.
    let stringsBlob =
        stringEntry(id: 1, bundleIDText)
        + stringEntry(id: 2, realContainer)

    let bundleIDRef: UInt32 = 1 << 2
    let containerRef: UInt32 = 2 << 2

    // 27.2-family fixture: bundle id at 0x0c → the 27.2 layout maps it.
    let store272 =
        Array("bdsl".utf8)
        + le32(UInt32(0x1000)) // header word
        + bundleRecord(bundleSize: 0x25c, bundleID: 0x0c, name: 0x70,
                       displayName: 0x78, container: 0x6c,
                       refs: (bundleIDRef, 0, 0, containerRef))
        + stringsBlob
    var padded272 = store272
    while padded272.count < 0x1000 { padded272.append(0) }

    if let snapshot = LaunchServicesStore.parse(Data(padded272)) {
        expect(snapshot.containerBundleIDs.values.contains(bundleIDText),
               "27.2 fixture: bundle id mapped")
        expect(["27.2", "27.2b", "27.2c", "27.2d", "27.3"].contains(snapshot.layoutLabel),
               "27.2 fixture: winning layout is the 0x25c family (got \(snapshot.layoutLabel))")
    } else {
        expect(false, "27.2 fixture: store failed to parse")
    }

    // 27.3 variant fixture: bundle id at 0x14 → only the 27.3b candidate
    // reads a valid ref there, so the 27.3 family must map the container.
    let store273 =
        Array("bdsl".utf8)
        + le32(UInt32(0x1000))
        + bundleRecord(bundleSize: 0x25c, bundleID: 0x14, name: 0x74,
                       displayName: 0x7c, container: 0x70,
                       refs: (bundleIDRef, 0, 0, containerRef))
        + stringsBlob
    var padded273 = store273
    while padded273.count < 0x1000 { padded273.append(0) }

    if let snapshot = LaunchServicesStore.parse(Data(padded273)) {
        expect(snapshot.containerBundleIDs.values.contains(bundleIDText),
               "27.3 fixture: bundle id mapped by a 27.3 candidate")
        expect(snapshot.layoutLabel == "27.3b",
               "27.3 fixture: winning layout is 27.3b (got \(snapshot.layoutLabel))")
    } else {
        expect(false, "27.3 fixture: store failed to parse")
    }
}

// MARK: - LanguageResolver (F-01)
//
// The resolver is the first thing that runs on a fresh install, and a wrong
// answer is invisible in testing (the UI just renders in the wrong language),
// so every documented branch gets an explicit case.
expect(LanguageResolver.resolve(preferred: ["zh-Hans-CN"]) == "zh-Hans", "zh-Hans-CN → zh-Hans")
expect(LanguageResolver.resolve(preferred: ["zh-Hant-TW"]) == "zh-Hans",
       "zh-Hant-TW → zh-Hans (no Traditional bundle ships)")
expect(LanguageResolver.resolve(preferred: ["zh-CN"]) == "zh-Hans", "lowercase/region zh-CN → zh-Hans")
expect(LanguageResolver.resolve(preferred: ["ko-KR"]) == "ko", "ko-KR → ko")
expect(LanguageResolver.resolve(preferred: ["ko"]) == "ko", "bare ko → ko")
expect(LanguageResolver.resolve(preferred: ["vi-VN"]) == "vi", "vi-VN → vi")
expect(LanguageResolver.resolve(preferred: ["en-US"]) == "en", "en-US → en")
expect(LanguageResolver.resolve(preferred: ["ja-JP"]) == "en", "unsupported language ja-JP → en")
expect(LanguageResolver.resolve(preferred: []) == "en", "empty preference list → en")

// Order matters: preferredLanguages puts the current system language first.
expect(LanguageResolver.resolve(preferred: ["en-US", "ko-KR"]) == "en",
       "first match wins: en-US before ko-KR → en")
expect(LanguageResolver.resolve(preferred: ["ko-KR", "en-US"]) == "ko",
       "first match wins: ko-KR before en-US → ko")
expect(LanguageResolver.resolve(preferred: ["ja-JP", "vi-VN"]) == "vi",
       "unknown first entry falls through to the next known one")

// seedIfNeeded must never overwrite an explicit choice made in Settings.
let resolverDefaults = UserDefaults(suiteName: "languageResolverTest")!
resolverDefaults.removePersistentDomain(forName: "languageResolverTest")
LanguageResolver.seedIfNeeded(defaults: resolverDefaults, preferred: ["ko-KR"], storageKey: "appLanguage")
expect(resolverDefaults.string(forKey: "appLanguage") == "ko", "seed writes the resolved language")
resolverDefaults.set("vi", forKey: "appLanguage")
LanguageResolver.seedIfNeeded(defaults: resolverDefaults, preferred: ["ko-KR"], storageKey: "appLanguage")
expect(resolverDefaults.string(forKey: "appLanguage") == "vi",
       "seed does not overwrite an existing explicit choice")
resolverDefaults.removePersistentDomain(forName: "languageResolverTest")

// MARK: - OnboardingStore (F-03)
//
// The regression this guards: an overwrite install of the same version must
// not replay onboarding. The old fingerprint compared executable mtime, which
// changes on every overwrite, so this test would have failed by design there.
expect(OnboardingStore.shouldShow(hasCompleted: false), "first install shows onboarding")
expectFalse(OnboardingStore.shouldShow(hasCompleted: true), "completed install hides onboarding")

let onboardingDefaults = UserDefaults(suiteName: "onboardingStoreTest")!
onboardingDefaults.removePersistentDomain(forName: "onboardingStoreTest")
expect(OnboardingStore.shouldShow(defaults: onboardingDefaults), "clean defaults → show")

onboardingDefaults.set(true, forKey: OnboardingStore.completedKey)
expectFalse(OnboardingStore.shouldShow(defaults: onboardingDefaults),
            "completed flag alone suppresses onboarding")

// Migration: a 3.2.6 install only has the legacy keys.
onboardingDefaults.removePersistentDomain(forName: "onboardingStoreTest")
onboardingDefaults.set("3.2.6 (25)", forKey: OnboardingStore.legacyVersionKey)
expectFalse(OnboardingStore.shouldShow(defaults: onboardingDefaults),
            "legacy completedVersion suppresses onboarding on upgrade")
expect(onboardingDefaults.bool(forKey: OnboardingStore.completedKey),
       "legacy migration writes the new completed flag")

onboardingDefaults.removePersistentDomain(forName: "onboardingStoreTest")
onboardingDefaults.set("3.2.6 (25)#1700000000", forKey: OnboardingStore.legacyFingerprintKey)
expectFalse(OnboardingStore.shouldShow(defaults: onboardingDefaults),
            "legacy completedFingerprint suppresses onboarding on upgrade")

// Empty legacy values are not evidence of completion — a key that exists but
// holds "" must still show onboarding, or a corrupted defaults file would skip
// the screen forever.
onboardingDefaults.removePersistentDomain(forName: "onboardingStoreTest")
onboardingDefaults.set("", forKey: OnboardingStore.legacyVersionKey)
expect(OnboardingStore.shouldShow(defaults: onboardingDefaults),
       "empty legacy value does not count as completed")

onboardingDefaults.removePersistentDomain(forName: "onboardingStoreTest")
OnboardingStore.markCompleted(defaults: onboardingDefaults)
expectFalse(OnboardingStore.shouldShow(defaults: onboardingDefaults), "markCompleted suppresses onboarding")
expect(onboardingDefaults.string(forKey: OnboardingStore.legacyVersionKey)?.isEmpty == false,
       "markCompleted keeps the legacy key readable for downgrades")
onboardingDefaults.removePersistentDomain(forName: "onboardingStoreTest")

// MARK: - SQLiteSidecarPolicy (F-06)
//
// The regression this guards: restoring a SQLite database wrote only the main
// file and left the live -wal in place, so the next open replayed the WAL over
// the restored database — the restore silently reverted.
let sqliteHeader = Data("SQLite format 3\0".utf8)
expect(SQLiteSidecarPolicy.hasSQLiteHeader(sqliteHeader), "exact 16-byte header matches")
expect(SQLiteSidecarPolicy.hasSQLiteHeader(sqliteHeader + Data([0x00, 0x01])),
       "header followed by page data still matches (prefix check)")
expectFalse(SQLiteSidecarPolicy.hasSQLiteHeader(Data("SQLite format 2\0".utf8)),
            "version 2 header is not SQLite 3")
expectFalse(SQLiteSidecarPolicy.hasSQLiteHeader(Data("SQLite for".utf8)),
            "truncated prefix does not match")
expectFalse(SQLiteSidecarPolicy.hasSQLiteHeader(Data()), "empty prefix does not match")

expect(SQLiteSidecarPolicy.sidecars(for: "/a/b.sqlite") == ["/a/b.sqlite-wal", "/a/b.sqlite-shm"],
       "sidecars are appended in -wal then -shm order")
expect(SQLiteSidecarPolicy.sidecars(for: "/a/b.sqlite").count == 2, "exactly two sidecars")

// Real-file detection: write a header-prefixed file, then a non-SQLite one.
let sqliteDir = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("sqliteSidecarTest-\(UUID().uuidString)")
try? FileManager.default.createDirectory(at: sqliteDir, withIntermediateDirectories: true)
let dbURL = sqliteDir.appendingPathComponent("test.sqlite")
try? (sqliteHeader + Data(repeating: 0x00, count: 100)).write(to: dbURL)
expect(SQLiteSidecarPolicy.isSQLiteFile(path: dbURL.path), "file with SQLite header detected")
let textURL = sqliteDir.appendingPathComponent("not-a-db.txt")
try? Data("hello world, definitely not sqlite".utf8).write(to: textURL)
expectFalse(SQLiteSidecarPolicy.isSQLiteFile(path: textURL.path), "plain text is not SQLite")
expectFalse(SQLiteSidecarPolicy.isSQLiteFile(path: sqliteDir.appendingPathComponent("missing.db").path),
            "missing file is not SQLite")
try? FileManager.default.removeItem(at: sqliteDir)

// MARK: - PlistDatePolicy (F-07)
//
// Two silent-loss regressions: XML plists round fractional seconds away on
// write, and an oversized file parses only its prefix, so the save truncates.
let wholeSecond = Date(timeIntervalSince1970: 1_763_546_400)   // 2025-11-19T00:00:00Z
let fractional = Date(timeIntervalSince1970: 1_763_546_400.5)

expect(PlistDatePolicy.hasFractionalSeconds(fractional), "fractional date detected")
expectFalse(PlistDatePolicy.hasFractionalSeconds(wholeSecond), "whole-second date is clean")
expect(PlistDatePolicy.truncateToWholeSecond(fractional).timeIntervalSince1970 == 1_763_546_400,
       "truncation floors to the whole second")
expect(PlistDatePolicy.truncateToWholeSecond(wholeSecond) == wholeSecond,
       "truncating an already-whole date is a no-op")

// XML rejects fractional input; binary keeps it.
expectFalse(PlistDatePolicy.canRepresentText("2025-11-19T10:00:00.500Z", format: .xml),
            "XML rejects fractional seconds")
expect(PlistDatePolicy.canRepresentText("2025-11-19T10:00:00Z", format: .xml),
       "XML accepts whole seconds")
expect(PlistDatePolicy.canRepresentText("2025-11-19T10:00:00.500Z", format: .binary),
       "binary keeps fractional seconds")
// A non-date string is a parse error, not a precision problem — don't mask it.
expect(PlistDatePolicy.canRepresentText("not a date", format: .xml),
       "unparseable text passes the precision check")

// Size limit.
expect(PlistDatePolicy.maximumBytes == 64 * 1024 * 1024, "limit is 64 MB")
expectFalse(PlistDatePolicy.exceedsSizeLimit(byteCount: 64 * 1024 * 1024), "exactly 64 MB allowed")
expect(PlistDatePolicy.exceedsSizeLimit(byteCount: 64 * 1024 * 1024 + 1), "64 MB + 1 byte refused")

let sizeDir = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("plistDatePolicyTest-\(UUID().uuidString)")
try? FileManager.default.createDirectory(at: sizeDir, withIntermediateDirectories: true)
let smallURL = sizeDir.appendingPathComponent("small.plist")
try? Data(repeating: 0x41, count: 1024).write(to: smallURL)
expectFalse(PlistDatePolicy.exceedsSizeLimit(fileAt: smallURL), "1 KB file allowed")
expectFalse(PlistDatePolicy.exceedsSizeLimit(fileAt: sizeDir.appendingPathComponent("nope.plist")),
            "missing file is not treated as oversized")
try? FileManager.default.removeItem(at: sizeDir)

// MARK: - PermissionPolicy (F-13)
//
// The octal and symbolic renderings must agree; a mismatch would show one mode
// and write another. The bit math is also the only place the preset ladder is
// defined, so a typo here ships a wrong chmod.
expect(PermissionPolicy.masked(0o10755) == 0o755, "setuid bit is stripped from the mask")
expect(PermissionPolicy.octalString(0o755) == "0755", "0755 renders four digits")
expect(PermissionPolicy.octalString(0o644) == "0644", "0644 renders four digits")
expect(PermissionPolicy.octalString(0o4777) == "0777", "setuid is masked out of the display")
expect(PermissionPolicy.symbolicString(0o755) == "rwxr-xr-x", "0755 symbolic form")
expect(PermissionPolicy.symbolicString(0o644) == "rw-r--r--", "0644 symbolic form")
expect(PermissionPolicy.symbolicString(0o444) == "r--r--r--", "0444 symbolic form")
expect(PermissionPolicy.symbolicString(0o555) == "r-xr-xr-x", "0555 symbolic form")
expect(PermissionPolicy.symbolicString(0o000) == "---------", "0000 has no bits set")

expect(PermissionPolicy.isReadOnly(0o444), "0444 is read-only")
expect(PermissionPolicy.isReadOnly(0o555), "0555 has no write bits, so read-only")
expectFalse(PermissionPolicy.isReadOnly(0o644), "0644 is writable by owner")
expectFalse(PermissionPolicy.isReadOnly(0o755), "0755 is writable by owner")

expect(PermissionPolicy.presets == [0o444, 0o555, 0o644, 0o755],
       "presets run least to most permissive")
expect(PermissionPolicy.isCurrent(0o755, preset: 0o755), "identical mode is current")
expectFalse(PermissionPolicy.isCurrent(0o755, preset: 0o555), "different mode is not current")
expect(PermissionPolicy.isCurrent(0o10755, preset: 0o755),
       "current comparison ignores bits above 0777")
expect(PermissionPolicy.presetLabel(0o555) == "0555 · r-xr-xr-x",
       "label shows octal and symbolic together")

// MARK: - A10 chip gate (F-08)
//
// A10 Fusion hangs inside the kernel chain on iOS 17. This is a chip gate, not
// an OS gate: the same iOS 17 version works on every other chip family, so the
// guard must be narrow enough not to shadow the existing version rules.
expectFalse(ExploitSupportPolicy.supportsKernelExploit(major: 17, minor: 7, patch: 9, isA10: true),
            "A10 + iOS 17.7 is refused")
expectFalse(ExploitSupportPolicy.supportsKernelExploit(major: 17, minor: 0, patch: 0, isA10: true),
            "A10 + iOS 17.0 is refused")
expect(ExploitSupportPolicy.supportsKernelExploit(major: 17, minor: 7, patch: 9),
       "non-A10 + iOS 17.7 still allowed (default arg preserved)")
expect(ExploitSupportPolicy.supportsKernelExploit(major: 18, minor: 0, patch: 0, isA10: true),
       "A10 + iOS 18.0 follows the normal rule")
expect(ExploitSupportPolicy.supportsKernelExploit(major: 18, minor: 7, patch: 1, isA10: true),
       "A10 + iOS 18.7.1 follows the normal rule")
expectFalse(ExploitSupportPolicy.supportsKernelExploit(major: 18, minor: 7, patch: 2, isA10: true),
            "A10 + iOS 18.7.2 refused by the version rule, not the chip rule")

// The A10 gate only removes kernel access; 26.x backends are unaffected
// because they never use the kernel chain.
expect(ExploitSupportPolicy.isSupported(major: 26, minor: 0, patch: 0, build: "any", isA10: true),
       "A10 does not lose bad_query on 26.0")
expectFalse(ExploitSupportPolicy.isSupported(major: 17, minor: 7, patch: 9, build: "any", isA10: true),
            "A10 + iOS 17 has no backend left, so it is unsupported")

// DeviceCPU.isA10(family:) is the testable half; the sysctl call is not.
// The literal must match CPUFAMILY_ARM_HURRICANE in mach/machine.h and in
// kexploit/machine_info.h — 0x2C91A47E is Typhoon (A8) and would disable the
// A10 + iOS 17 guard on every real A10 device.
expect(DeviceCPU.isA10(family: DeviceCPU.a10Family), "A10 family id recognised")
expect(DeviceCPU.a10Family == 0x67CEEE93, "A10 family literal is Hurricane")
expectFalse(DeviceCPU.isA10(family: DeviceCPU.typhoonFamily), "Typhoon (A8) is not A10")
expect(DeviceCPU.typhoonFamily == 0x2C91A47E, "Typhoon literal matches Apple's header")
expectFalse(DeviceCPU.isA10(family: 0x07D34B9F), "Vortex/Tempest (A12) is not A10")
expectFalse(DeviceCPU.isA10(family: nil), "unreadable cpu family is not A10")

// Rejection copy: A10+iOS 17 must produce its own explanation rather than the
// generic "iOS X is unsupported" text, which would wrongly imply an OS update
// is the fix.
let a10Reason = RejectionReason.make(
    major: 17, minor: 7, patch: 9, build: "21H16", osVersion: "iOS 17.7.9 (21H16)", isA10: true
)
expect(a10Reason != nil, "A10 + iOS 17 yields a rejection reason")
expect(a10Reason?.arguments.isEmpty == true, "the A10 copy needs no version interpolation")
expect(a10Reason?.key != "status.unsupported_reason",
       "A10 rejection uses its own key, not the generic OS one")
expect(RejectionReason.make(
    major: 17, minor: 7, patch: 9, build: "21H16", osVersion: "iOS 17.7.9 (21H16)"
) == nil, "non-A10 + iOS 17.7 has no rejection")

// MARK: - JailbreakDetector (F-09)
//
// Substring matching, not path equality: rootless jailbreaks remap the
// bootstrap under /var/jb, so exact paths would miss the common case.
expect(JailbreakDetector.isJailbroken(imagePaths: ["/usr/lib/libsubstitute.dylib"]),
       "Substitute detected")
expect(JailbreakDetector.isJailbroken(imagePaths: ["/usr/lib/substrate/SubstrateLoader.dylib"]),
       "Cydia Substrate detected")
expect(JailbreakDetector.isJailbroken(
    imagePaths: ["/var/jb/Library/MobileSubstrate/DynamicLibraries/ElleKit.dylib"]
), "ElleKit under /var/jb detected")
expect(JailbreakDetector.isJailbroken(imagePaths: ["/usr/lib/libhooker.dylib"]),
       "libhooker detected")
expect(JailbreakDetector.isJailbroken(imagePaths: ["/var/jb/usr/lib/libpthread.dylib"]),
       "bare /var/jb prefix detected")
expectFalse(JailbreakDetector.isJailbroken(imagePaths: []),
            "empty image list is not jailbroken")
expectFalse(JailbreakDetector.isJailbroken(imagePaths: [
    "/System/Library/Frameworks/Foundation.framework/Foundation",
    "/usr/lib/libSystem.B.dylib",
    "/private/var/containers/Bundle/Application/3106.app/3106",
]), "stock system images are clean")

// Substring matching has a known false-positive shape: any path containing an
// indicator string matches. That is accepted deliberately — a false positive
// costs one capability on a device that is probably jailbroken anyway, while a
// false negative reports a verdict it cannot stand behind.
expect(JailbreakDetector.isJailbroken(imagePaths: ["/usr/lib/libsubstitute_helper"]),
       "substring match is intentionally broad")
expectFalse(JailbreakDetector.isJailbroken(imagePaths: ["/usr/lib/libobjc.A.dylib"]),
            "unrelated system library is clean")

expect(JailbreakDetector.matchedIndicator(imagePaths: ["/usr/lib/libobjc.A.dylib",
                                                     "/var/jb/Library/ElleKit.dylib"]) != nil,
       "matchedIndicator reports the hit")
expect(JailbreakDetector.matchedIndicator(imagePaths: ["/usr/lib/libobjc.A.dylib"]) == nil,
       "matchedIndicator is nil on a clean list")

// The refusal rule is scoped to the kernel backend.
expect(JailbreakDetector.refusesKernelChain(isJailbroken: true, isKernelBackend: true),
       "jailbroken + kernel → refuse")
expectFalse(JailbreakDetector.refusesKernelChain(isJailbroken: false, isKernelBackend: true),
            "clean + kernel → run")
expectFalse(JailbreakDetector.refusesKernelChain(isJailbroken: true, isKernelBackend: false),
            "jailbroken + system backend → still run (verdict stays attributable)")
expectFalse(JailbreakDetector.refusesKernelChain(isJailbroken: false, isKernelBackend: false),
            "clean + system backend → run")

// MARK: - RegionKeyPolicy (F-10)
//
// `legacyRegionInfo` is RegionInfoFromSysconfig, the key the system reads;
// `regionInfo` is a non-cache key on iOS 27 that older tools injected. Both
// can exist with different values, and the sysconfig one must win — reading
// the injected key first made a correctly changed region look unchanged.
let newKey = "new-region-info"
let legacyKey = "legacy-region-info"
let codeKey = "region-code"

var bothKeys: [String: Any] = [newKey: "CH/A", legacyKey: "LL/A", codeKey: "LL"]
expect(RegionKeyPolicy.infoKey(in: bothKeys, regionInfo: newKey, legacyRegionInfo: legacyKey) == legacyKey,
       "RegionInfoFromSysconfig wins when both keys exist")
expect(RegionKeyPolicy.regionValue(in: bothKeys, regionInfo: newKey, legacyRegionInfo: legacyKey) == "LL/A",
       "the effective value is the sysconfig one, not the stale non-cache key")

var onlyNew: [String: Any] = [newKey: "JP/", codeKey: "J"]
expect(RegionKeyPolicy.infoKey(in: onlyNew, regionInfo: newKey, legacyRegionInfo: legacyKey) == newKey,
       "device with only the newer key is readable")
expect(RegionKeyPolicy.regionValue(in: onlyNew, regionInfo: newKey, legacyRegionInfo: legacyKey) == "JP/",
       "value read from the newer key")
var onlyLegacy: [String: Any] = [legacyKey: "TA/A", codeKey: "TA"]
expect(RegionKeyPolicy.infoKey(in: onlyLegacy, regionInfo: newKey, legacyRegionInfo: legacyKey) == legacyKey,
       "device with only the legacy key is readable")
expect(RegionKeyPolicy.infoKey(in: [codeKey: "LL"], regionInfo: newKey, legacyRegionInfo: legacyKey) == nil,
       "no -info key at all is reported as missing")
expect(RegionKeyPolicy.regionValue(in: [codeKey: "LL"], regionInfo: newKey, legacyRegionInfo: legacyKey) == nil,
       "regionValue is nil when no -info key exists")

expect(RegionKeyPolicy.regionText(for: "LL") == "LL/A", "region text is code + /A")
expect(RegionKeyPolicy.regionText(for: "ZP") == "ZP/A", "region text for Hong Kong")

// apply: writes only keys that already exist, and never invents one.
var target: [String: Any] = [newKey: "CH/A", legacyKey: "CH/A", codeKey: "CH"]
let written = RegionKeyPolicy.apply(
    code: "LL", to: &target, regionCode: codeKey, regionInfo: newKey, legacyRegionInfo: legacyKey
)
expect(target[newKey] as? String == "LL/A", "newer key updated")
expect(target[legacyKey] as? String == "LL/A", "legacy key kept in sync")
expect(target[codeKey] as? String == "LL", "country code updated")
expect(written.count == 3, "three keys reported written when all exist")

var legacyOnlyTarget: [String: Any] = [legacyKey: "CH/A", codeKey: "CH"]
_ = RegionKeyPolicy.apply(
    code: "J", to: &legacyOnlyTarget, regionCode: codeKey, regionInfo: newKey, legacyRegionInfo: legacyKey
)
expect(legacyOnlyTarget[newKey] == nil, "a key the device never had is NOT invented")
expect(legacyOnlyTarget[legacyKey] as? String == "J/A", "the existing key is updated")

var newOnlyTarget: [String: Any] = [newKey: "CH/A", codeKey: "CH"]
_ = RegionKeyPolicy.apply(
    code: "TA", to: &newOnlyTarget, regionCode: codeKey, regionInfo: newKey, legacyRegionInfo: legacyKey
)
expect(newOnlyTarget[legacyKey] == nil, "legacy key is not injected on an iOS 27-only cache")
expect(newOnlyTarget[newKey] as? String == "TA/A", "the newer key is updated")

// MARK: - RegionTargets (F-11)
//
// The region list is data, so the failure mode is a duplicate or missing code
// rather than a crash — writing the wrong prefix silently moves the device to
// a different country rather than erroring.
expect(RegionTargets.all.count == 15, "fifteen region targets")
let codes = RegionTargets.all.map(\.code)
expect(Set(codes).count == codes.count, "region codes are unique")
let countries = RegionTargets.all.map(\.country)
expect(Set(countries).count == countries.count, "country codes are unique")
expect(RegionTargets.all.allSatisfy { !$0.code.isEmpty && !$0.country.isEmpty },
       "no empty code or country")

// Every expected market is present, so a future edit cannot silently drop one.
let expected: Set<String> = ["US","JP","CN","HK","TW","KR","GB","DE","FR","CA","AU","SG","IN","VN","AE"]
expect(Set(countries) == expected, "all fifteen markets present")
expect(RegionTargets.all.first?.country == "US", "US leads the list")
expect(RegionTargets.all.first?.code == "LL", "US region prefix is LL")

expect(RegionTargets.all.first { $0.country == "JP" }?.regionText == "J/A",
       "Japan region text is J/A")
expect(RegionTargets.all.first { $0.country == "CN" }?.regionText == "CH/A",
       "China region text is CH/A")
expect(RegionTargets.all.first { $0.country == "VN" }?.regionText == "VN/A",
       "Vietnam region text is VN/A")

// Round trip: whatever the device reports resolves back to the same target.
for target in RegionTargets.all {
    let resolved = RegionTargets.target(forRegionText: target.regionText)
    expect(resolved?.code == target.code,
           "\(target.country) region text round-trips to its own target")
}
// Unknown regions must not resolve — the picker shows them as "not in list".
expect(RegionTargets.target(forRegionText: "ZZ/A") == nil, "unknown region does not resolve")
expect(RegionTargets.target(forRegionText: "ZZ") == nil, "bare unknown code does not resolve")
expect(RegionTargets.target(forRegionText: "LL")?.code == "LL",
       "a region text without the /A suffix still resolves")

expect(RegionTargets.target(country: "KR")?.code == "KH", "country lookup returns Korea")
expect(RegionTargets.target(country: "ZZ") == nil, "unknown country lookup is nil")

// MARK: - WiFiSharePolicy (F-12)
//
// The server hands a stranger on the LAN access to the user's container behind
// one 6-digit PIN, so the auth comparison, path containment and overwrite rules
// are the security surface. None of them need a socket to test.

// PIN: six digits, uniform by rejection.
expect(WiFiSharePolicy.generatePIN(uniform: { 0 }).count == 6, "PIN has six digits")
expect(WiFiSharePolicy.generatePIN(uniform: { 0 }) == "000000", "zero draws yield all zeros")
expect(WiFiSharePolicy.generatePIN(uniform: { 9 }) == "999999", "max drawn digit repeats")
expect(Set(WiFiSharePolicy.generatePIN().unicodeScalars).allSatisfy { $0.value >= 48 && $0.value <= 57 },
       "a generated PIN is all decimal digits")
// Rejection: values at or above the limit are discarded, not folded in.
var draws: [UInt32] = [UInt32.max, 11, 12, 13, 14, 15, 16]
expect(WiFiSharePolicy.generatePIN(uniform: { draws.removeFirst() }) == "123456",
       "out-of-range draws are rejected, then digits taken in order")

// Basic Auth.
expect(WiFiSharePolicy.expectedAuthorization(pin: "123456").hasPrefix("Basic "),
       "authorization value is a Basic credential")
expect(WiFiSharePolicy.isAuthorized(
    header: WiFiSharePolicy.expectedAuthorization(pin: "123456"), pin: "123456"
), "the correct credential is accepted")
expectFalse(WiFiSharePolicy.isAuthorized(
    header: WiFiSharePolicy.expectedAuthorization(pin: "123456"), pin: "123457"
), "a different PIN is rejected")
expectFalse(WiFiSharePolicy.isAuthorized(header: nil, pin: "123456"),
            "a missing header is rejected (no anonymous access)")
expectFalse(WiFiSharePolicy.isAuthorized(header: "Basic ", pin: "123456"),
            "an empty credential is rejected")
expectFalse(WiFiSharePolicy.isAuthorized(header: "Bearer \(WiFiSharePolicy.expectedAuthorization(pin: "123456").dropFirst(6))", pin: "123456"),
            "the scheme must match exactly")

// Header parsing is case-insensitive on the name, as HTTP requires.
let headers = "Host: 1.2.3.4\r\nAuthorization: Basic abc\r\nContent-Length: 42\r\n"
expect(WiFiSharePolicy.authorizationHeader(in: headers) == "Basic abc",
       "Authorization extracted")
expect(WiFiSharePolicy.contentLength(in: headers) == 42, "Content-Length extracted")
expect(WiFiSharePolicy.authorizationHeader(in: "authorization: Basic xyz") == "Basic xyz",
       "header name is matched case-insensitively")
expect(WiFiSharePolicy.contentLength(in: "Host: x") == nil, "absent Content-Length is nil")

// Request line.
let line = WiFiSharePolicy.parseRequestLine("GET /api/download?path=a%2Fb.txt HTTP/1.1")
expect(line?.method == "GET", "method parsed")
expect(line?.path == "/api/download", "path separated from query")
expect(line?.query == "path=a%2Fb.txt", "query preserved")
expect(WiFiSharePolicy.parseRequestLine("PUT /api/upload HTTP/1.0")?.query == "",
       "absent query is empty, not nil")
expect(WiFiSharePolicy.parseRequestLine("garbage") == nil, "malformed request line is nil")
expect(WiFiSharePolicy.parseRequestLine("GET relative/path HTTP/1.1") == nil,
       "a non-absolute target is rejected")
expect(WiFiSharePolicy.queryParameter("path", in: "path=a%2Fb.txt&x=1") == "a/b.txt",
       "query parameter percent-decoded")
expect(WiFiSharePolicy.queryParameter("missing", in: "a=1") == nil,
       "absent parameter is nil")

// Path containment: the whole point is that nothing escapes the root.
let shareRoot = URL(fileURLWithPath: "/var/mobile/Documents/3106/Transfer")
expect(WiFiSharePolicy.containedPath("/photo.jpg", within: shareRoot)?.lastPathComponent == "photo.jpg",
       "a plain name resolves inside the root")
expect(WiFiSharePolicy.containedPath("/sub/photo.jpg", within: shareRoot)?.lastPathComponent == "photo.jpg",
       "a nested path resolves inside the root")
expect(WiFiSharePolicy.containedPath("/../escape.txt", within: shareRoot) == nil,
       "traversal is refused")
expect(WiFiSharePolicy.containedPath("/sub/../../escape.txt", within: shareRoot) == nil,
       "nested traversal is refused")
expect(WiFiSharePolicy.containedPath("/%2e%2e/escape.txt", within: shareRoot) == nil,
       "percent-encoded traversal is refused before decoding")
expect(WiFiSharePolicy.containedPath("photo.jpg", within: shareRoot) == nil,
       "a relative target is refused (no leading slash)")

// Upload naming: never overwrite.
let taken: Set<String> = ["report.txt"]
expect(WiFiSharePolicy.uniqueDestination(for: "new.txt", existing: { taken.contains($0) }) == "new.txt",
       "a free name is kept as-is")
expect(WiFiSharePolicy.uniqueDestination(for: "report.txt", existing: { taken.contains($0) }) == "report 2.txt",
       "a colliding name climbs to 2")
let busy: Set<String> = ["report.txt", "report 2.txt", "report 3.txt"]
expect(WiFiSharePolicy.uniqueDestination(for: "report.txt", existing: { busy.contains($0) }) == "report 4.txt",
       "climbing skips every taken name")
expect(WiFiSharePolicy.uniqueDestination(for: "README", existing: { $0 == "README" }) == "README 2",
       "an extension-less name climbs without a dot")
expect(WiFiSharePolicy.uniqueDestination(for: "a.tar.gz", existing: { $0 == "a.tar.gz" }) == "a.tar 2.gz",
       "only the last extension is preserved")

// Port ladder.
expect(WiFiSharePolicy.portRange.first == 8080, "starts at 8080")
expect(WiFiSharePolicy.portRange.last == 8090, "spans eleven ports")
expect(WiFiSharePolicy.maximumZipBytes == 2 * 1024 * 1024 * 1024, "zip cap is 2 GB")

// MARK: - Explicit unlock predicate (F-14)
//
// The kernel chain used to run at launch. The rule that replaced it must stay
// narrow: only the kernel backend needs an unlock event, because bad_query and
// worse_query grant access through system APIs that need no exploit. If this
// predicate widened, every iOS 26/27 user would see a banner for a step that
// does nothing.
expect(ExploitSupportPolicy.requiresExplicitUnlock(isKernelBackend: true, hasAccess: false),
       "kernel backend without access needs an unlock")
expectFalse(ExploitSupportPolicy.requiresExplicitUnlock(isKernelBackend: true, hasAccess: true),
            "an already-unlocked kernel device shows no banner")
expectFalse(ExploitSupportPolicy.requiresExplicitUnlock(isKernelBackend: false, hasAccess: false),
            "bad_query / worse_query never need an unlock")
expectFalse(ExploitSupportPolicy.requiresExplicitUnlock(isKernelBackend: false, hasAccess: true),
            "a working system backend needs no unlock either")

if failures == 0 {
    print("PASS: \(checks) policy checks")
    exit(0)
} else {
    print("FAILED: \(failures)/\(checks) checks")
    exit(1)
}