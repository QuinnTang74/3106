import Foundation

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

// iOS 17 kernel range
expect(ExploitSupportPolicy.supportsKernelExploit(major: 17, minor: 0, patch: 0), "17.0 kernel")
expect(ExploitSupportPolicy.supportsKernelExploit(major: 17, minor: 7, patch: 9), "17.7.x kernel")
expectFalse(ExploitSupportPolicy.supportsKernelExploit(major: 17, minor: 8, patch: 0), "17.8 not kernel")
expectFalse(ExploitSupportPolicy.supportsKernelExploit(major: 16, minor: 7, patch: 0), "16.x not kernel")

// iOS 18 kernel range
expect(ExploitSupportPolicy.supportsKernelExploit(major: 18, minor: 0, patch: 0), "18.0 kernel")
expect(ExploitSupportPolicy.supportsKernelExploit(major: 18, minor: 7, patch: 1), "18.7.1 kernel")
expectFalse(ExploitSupportPolicy.supportsKernelExploit(major: 18, minor: 7, patch: 2), "18.7.2 not kernel")

// bad_query range
expect(ExploitSupportPolicy.supportsBadQuery(major: 26, minor: 0, patch: 0), "26.0 bad_query")
expect(ExploitSupportPolicy.supportsBadQuery(major: 26, minor: 6, patch: 1), "26.6.1 bad_query")
expectFalse(ExploitSupportPolicy.supportsBadQuery(major: 26, minor: 6, patch: 2), "26.6.2 not bad_query")
expectFalse(ExploitSupportPolicy.supportsBadQuery(major: 26, minor: 7, patch: 0), "26.7 not bad_query")

// worse_query range
expectFalse(ExploitSupportPolicy.supportsWorseQuery(major: 26, minor: 6, patch: 9), "26.6.9 not worse_query")
expect(ExploitSupportPolicy.supportsWorseQuery(major: 26, minor: 7, patch: 0), "26.7.0 worse_query")
expect(ExploitSupportPolicy.supportsWorseQuery(major: 26, minor: 7, patch: 2), "26.7.2 worse_query")
expectFalse(ExploitSupportPolicy.supportsWorseQuery(major: 26, minor: 7, patch: 3), "26.7.3 not worse_query")
expect(ExploitSupportPolicy.supportsWorseQuery(major: 27, minor: 0, patch: 0), "27.0 worse_query")
expect(ExploitSupportPolicy.supportsWorseQuery(major: 27, minor: 2, patch: 0), "27.2 worse_query")
expectFalse(ExploitSupportPolicy.supportsWorseQuery(major: 27, minor: 3, patch: 0), "27.3 not verified worse_query")
expectFalse(ExploitSupportPolicy.supportsWorseQuery(major: 28, minor: 0, patch: 0), "28.0 not worse_query")

// Experimental + overall support
expect(ExploitSupportPolicy.isExperimental(major: 27, minor: 3), "27.3 experimental")
expectFalse(ExploitSupportPolicy.isExperimental(major: 27, minor: 2), "27.2 not experimental")

expect(ExploitSupportPolicy.isSupported(major: 26, minor: 7, patch: 2, build: "any"), "26.7.2 supported")
expect(ExploitSupportPolicy.isSupported(major: 27, minor: 2, patch: 0, build: "any"), "27.2 supported")
expect(ExploitSupportPolicy.isSupported(major: 27, minor: 3, patch: 0, build: "any"), "27.3 experimental supported")
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

if failures == 0 {
    print("PASS: \(checks) policy checks")
    exit(0)
} else {
    print("FAILED: \(failures)/\(checks) checks")
    exit(1)
}