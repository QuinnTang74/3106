//
//  worse_query.m
//  3106
//
//  worse_query sandbox escape by Taj C (forcequitOS):
//  https://github.com/forcequitOS/worse_query, GPL-3.0-or-later.
//
//  The Library/Caches swap, durable marker, recovery and open-verification
//  helpers are adapted from WQ Files by Christoph Kolbicz:
//  https://github.com/kolbicz/WQFiles, GPL-3.0-or-later.
//
//  This file is part of 3106, which is distributed under GPL-3.0.
//

#import "worse_query.h"

#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>
#include <xpc/xpc.h>

typedef struct __SecTask *SecTaskRef;
typedef SecTaskRef (*SecTaskCreateFromSelfFn)(CFAllocatorRef);
typedef CFTypeRef (*SecTaskCopyEntitlementFn)(SecTaskRef, CFStringRef, CFErrorRef *);

typedef void *(*cq_create_fn)(void);
typedef void (*cq_set_u64_fn)(void *, uint64_t);
typedef void (*cq_set_ids_fn)(void *, xpc_object_t);
typedef void *(*cq_result_fn)(void *);
typedef void (*cq_free_fn)(void *);
typedef char *(*cq_token_fn)(void *);
typedef int64_t (*ext_consume_fn)(const char *);
typedef int (*ext_release_fn)(int64_t);
typedef void (*cq_iterate_fn)(void *, bool (^)(void *));
typedef const char *(*co_get_path_fn)(void *);
typedef const char *(*co_get_id_fn)(void *);

static const NSUInteger WQCacheLimit = 192;
static const char *const WQCacheMarker = ".wq-caches-swap.plist";
static const char *const WQCacheMarkerTemp = ".wq-caches-swap.plist.tmp";
static const char *const WQCacheSaved = ".wq-caches-preserved";
static const char *const WQCacheLock = ".wq-caches-lock";

static NSRecursiveLock *gWQLock;
static NSMutableDictionary<NSString *, NSNumber *> *gWQCache;
static NSMutableArray<NSString *> *gWQOrder;

static void WQInit(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gWQLock = [NSRecursiveLock new];
        gWQCache = [NSMutableDictionary new];
        gWQOrder = [NSMutableArray new];
    });
}

static void WQReleaseToken(int64_t handle)
{
    if (handle < 0) return;
    static ext_release_fn release;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        release = (ext_release_fn)dlsym(RTLD_DEFAULT, "sandbox_extension_release");
    });
    if (release) (void)release(handle);
}

// MARK: - Portable safety helpers (adapted from WQ Files, GPL-3.0)

static BOOL WQSameObject(const struct stat *a, const struct stat *b)
{
    return a->st_dev == b->st_dev && a->st_ino == b->st_ino;
}

static NSString *WQCanonicalVarPath(NSString *path)
{
    if ([path isEqualToString:@"/var"] || [path hasPrefix:@"/var/"])
        return [@"/private" stringByAppendingString:path];
    return path;
}

static BOOL WQAbsolutePathGrammar(NSString *path)
{
    if (![path hasPrefix:@"/"] || path.length < 2 ||
        [path rangeOfString:@"\0"].location != NSNotFound) return NO;
    NSArray<NSString *> *parts = [path componentsSeparatedByString:@"/"];
    for (NSUInteger i = 1; i < parts.count; i++) {
        NSString *part = parts[i];
        if (!part.length || [part isEqualToString:@"."] || [part isEqualToString:@".."]) return NO;
    }
    return YES;
}

static int WQOpenDirectoryNoLinksFlags(NSString *path, int flags)
{
    path = WQCanonicalVarPath(path);
    if (!WQAbsolutePathGrammar(path)) { errno = EINVAL; return -1; }
    int fd = open("/", O_SEARCH | O_CLOEXEC);
    if (fd < 0) return -1;
    for (NSString *part in [path componentsSeparatedByString:@"/"]) {
        if (!part.length) continue;
        int next = openat(fd, part.fileSystemRepresentation,
                          O_SEARCH | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
        int error = errno;
        close(fd);
        if (next < 0) { errno = error; return -1; }
        fd = next;
    }
    if (flags == O_SEARCH) return fd;
    int result = openat(fd, ".", flags | O_DIRECTORY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
    int error = errno;
    close(fd);
    if (result < 0) errno = error;
    return result;
}

static int WQOpenDirectoryNoLinks(NSString *path)
{
    return WQOpenDirectoryNoLinksFlags(path, O_RDONLY);
}

static int WQOpenRegularAt(int parent, const char *name, int flags, mode_t mode)
{
    if (flags & O_TRUNC) { errno = EINVAL; return -1; }
    struct stat entry;
    if (fstatat(parent, name, &entry, AT_SYMLINK_NOFOLLOW) == 0) {
        if (!S_ISREG(entry.st_mode)) { errno = EINVAL; return -1; }
    } else if (errno != ENOENT || !(flags & O_CREAT)) {
        return -1;
    }
    int fd = openat(parent, name, flags | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC, mode);
    if (fd < 0) return -1;
    struct stat st = {0};
    if (fstat(fd, &st) != 0 || !S_ISREG(st.st_mode)) {
        int error = errno;
        if (!S_ISREG(st.st_mode)) error = EINVAL;
        close(fd);
        errno = error;
        return -1;
    }
    return fd;
}

static BOOL WQWriteBytes(int fd, NSData *data)
{
    const uint8_t *bytes = data.bytes;
    size_t done = 0;
    while (done < data.length) {
        ssize_t written = write(fd, bytes + done, data.length - done);
        if (written < 0 && errno == EINTR) continue;
        if (written <= 0) {
            if (written == 0) errno = EIO;
            return NO;
        }
        done += (size_t)written;
    }
    return fsync(fd) == 0;
}

static BOOL WQCacheInvalidMarkerCanBeDiscarded(int library)
{
    struct stat saved, caches;
    if (fstatat(library, WQCacheSaved, &saved, AT_SYMLINK_NOFOLLOW) == 0) {
        errno = EEXIST;
        return NO;
    }
    if (errno != ENOENT) return NO;
    if (fstatat(library, "Caches", &caches, AT_SYMLINK_NOFOLLOW) != 0) return NO;
    if (!S_ISDIR(caches.st_mode)) { errno = EINVAL; return NO; }
    if (unlinkat(library, WQCacheMarker, 0) != 0) return NO;
    return fsync(library) == 0;
}

/// Human-readable swap state for the log: which of the three entries exist,
/// and whether `Caches` is a link (and to where). Mirrors WQ Files'
/// wq_cache_state; without it a failing grant gives no clue which entry is
/// stuck.
static NSString *WQCacheStateString(int library)
{
    struct stat st;
    BOOL marker = fstatat(library, WQCacheMarker, &st, AT_SYMLINK_NOFOLLOW) == 0;
    BOOL saved = fstatat(library, WQCacheSaved, &st, AT_SYMLINK_NOFOLLOW) == 0;
    NSString *caches = @"missing";
    if (fstatat(library, "Caches", &st, AT_SYMLINK_NOFOLLOW) == 0) {
        if (S_ISLNK(st.st_mode)) {
            char link[4096];
            ssize_t n = readlinkat(library, "Caches", link, sizeof(link) - 1);
            if (n > 0) {
                link[n] = 0;
                caches = [NSString stringWithFormat:@"link -> %s", link];
            } else {
                caches = @"link";
            }
        } else if (S_ISDIR(st.st_mode)) {
            caches = @"directory";
        } else {
            caches = @"non-directory";
        }
    }
    return [NSString stringWithFormat:@"marker=%@ preserved=%@ Caches=%@",
            marker ? @"yes" : @"no", saved ? @"yes" : @"no", caches];
}

/// Puts `Library/Caches` back to a plain folder whatever state it is in.
///
/// Ported from WQ Files (`WQAccessSafety.h`, WQCacheSwapReset). This is the
/// repair path our 3.2.7 port was missing: when another worse_query app
/// sharing the App Group, an interrupted swap, or an older build leaves a
/// link/inode the recovery refuses, `WQCacheSwapBegin` used to fail forever
/// and every grant returned -4 (`tried=[]`). Nothing here is deleted —
/// anything in the way is renamed to `.wq-caches-reset-<uuid>`.
static BOOL WQCacheSwapReset(int library, NSMutableArray<NSString *> *done)
{
    if (unlinkat(library, WQCacheMarkerTemp, 0) == 0) {
        [done addObject:@"removed the temporary marker"];
    }
    NSString *(^aside)(void) = ^NSString *{
        return [@".wq-caches-reset-" stringByAppendingString:NSUUID.UUID.UUIDString];
    };
    struct stat st;
    if (fstatat(library, "Caches", &st, AT_SYMLINK_NOFOLLOW) == 0) {
        if (S_ISLNK(st.st_mode)) {
            if (unlinkat(library, "Caches", 0) != 0) return NO;
            [done addObject:@"removed the Caches link"];
        } else if (!S_ISDIR(st.st_mode)) {
            NSString *name = aside();
            if (renameatx_np(library, "Caches", library, name.fileSystemRepresentation,
                             RENAME_EXCL) != 0) return NO;
            [done addObject:[@"moved a non-folder Caches to " stringByAppendingString:name]];
        }
    } else if (errno != ENOENT) {
        return NO;
    }
    if (fstatat(library, WQCacheSaved, &st, AT_SYMLINK_NOFOLLOW) == 0) {
        BOOL cachesFree = fstatat(library, "Caches", &st, AT_SYMLINK_NOFOLLOW) != 0
            && errno == ENOENT;
        if (cachesFree) {
            if (renameatx_np(library, WQCacheSaved, library, "Caches",
                             RENAME_EXCL) != 0) return NO;
            [done addObject:@"restored the preserved Caches"];
        } else {
            NSString *name = aside();
            if (renameatx_np(library, WQCacheSaved, library, name.fileSystemRepresentation,
                             RENAME_EXCL) != 0) return NO;
            [done addObject:[@"moved the preserved Caches to " stringByAppendingString:name]];
        }
    } else if (errno != ENOENT) {
        return NO;
    }
    if (unlinkat(library, WQCacheMarker, 0) == 0) {
        [done addObject:@"removed the swap marker"];
    } else if (errno != ENOENT) {
        return NO;
    }
    if (fstatat(library, "Caches", &st, AT_SYMLINK_NOFOLLOW) != 0) {
        if (errno != ENOENT || mkdirat(library, "Caches", 0755) != 0) return NO;
        [done addObject:@"created Caches"];
    } else if (!S_ISDIR(st.st_mode)) {
        errno = EINVAL;
        return NO;
    }
    return fsync(library) == 0;
}

/// Repair-only lock open: a lock that isn't a regular file (link, folder,
/// fifo…) is moved aside with a no-replace rename; its target is never
/// followed or removed. Token requests keep refusing such an entry.
static int WQCacheLockOpenForRepair(int library, NSMutableArray<NSString *> *done)
{
    int lock = WQOpenRegularAt(library, WQCacheLock, O_RDWR | O_CREAT, 0600);
    if (lock >= 0) return lock;
    struct stat st;
    if (fstatat(library, WQCacheLock, &st, AT_SYMLINK_NOFOLLOW) != 0) return -1;
    if (S_ISREG(st.st_mode)) {
        errno = EBUSY;
        return -1;
    }
    NSString *name = [@".wq-caches-lock-quarantine-"
                      stringByAppendingString:NSUUID.UUID.UUIDString];
    if (renameatx_np(library, WQCacheLock, library, name.fileSystemRepresentation,
                     RENAME_EXCL) != 0) return -1;
    struct stat moved;
    BOOL same = fstatat(library, name.fileSystemRepresentation, &moved,
                        AT_SYMLINK_NOFOLLOW) == 0 && WQSameObject(&moved, &st);
    NSString *kind = S_ISLNK(st.st_mode) ? @"link"
                   : S_ISDIR(st.st_mode) ? @"folder" : @"special file";
    [done addObject:[NSString stringWithFormat:@"moved a non-regular lock (%@%@) to %@",
                     kind, same ? @"" : @", replaced meanwhile", name]];
    lock = WQOpenRegularAt(library, WQCacheLock, O_RDWR | O_CREAT | O_EXCL, 0600);
    if (lock < 0) return -1;
    if (fsync(library) != 0) {
        int err = errno;
        close(lock);
        errno = err;
        return -1;
    }
    [done addObject:@"created a new lock"];
    return lock;
}

static BOOL WQCacheSwapRecover(int library)
{
    int marker = WQOpenRegularAt(library, WQCacheMarker, O_RDONLY, 0);
    if (marker < 0) {
        if (errno != ENOENT) return NO;
        struct stat saved;
        if (fstatat(library, WQCacheSaved, &saved, AT_SYMLINK_NOFOLLOW) == 0) {
            errno = EEXIST;
            return NO;
        }
        return errno == ENOENT;
    }
    struct stat markerStat;
    if (fstat(marker, &markerStat) != 0 || markerStat.st_size <= 0 || markerStat.st_size > 65536) {
        close(marker);
        errno = EINVAL;
        return WQCacheInvalidMarkerCanBeDiscarded(library);
    }
    NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)markerStat.st_size];
    size_t done = 0;
    while (done < data.length) {
        ssize_t readBytes = read(marker, (uint8_t *)data.mutableBytes + done, data.length - done);
        if (readBytes < 0 && errno == EINTR) continue;
        if (readBytes <= 0) {
            close(marker);
            errno = EIO;
            return WQCacheInvalidMarkerCanBeDiscarded(library);
        }
        done += (size_t)readBytes;
    }
    close(marker);

    id record = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:nil];
    if (![record isKindOfClass:NSDictionary.class] ||
        ![record[@"Format"] isEqual:@1] ||
        ![record[@"Device"] isKindOfClass:NSNumber.class] ||
        ![record[@"Inode"] isKindOfClass:NSNumber.class] ||
        ![record[@"Target"] isKindOfClass:NSString.class]) {
        errno = EINVAL;
        return WQCacheInvalidMarkerCanBeDiscarded(library);
    }

    struct stat original = {0}, current = {0};
    original.st_dev = (dev_t)[record[@"Device"] intValue];
    original.st_ino = (ino_t)[record[@"Inode"] unsignedLongLongValue];
    BOOL savedExists = fstatat(library, WQCacheSaved, &original, AT_SYMLINK_NOFOLLOW) == 0;
    if (!savedExists && errno != ENOENT) return NO;

    struct stat expected = {0};
    expected.st_dev = (dev_t)[record[@"Device"] intValue];
    expected.st_ino = (ino_t)[record[@"Inode"] unsignedLongLongValue];
    if (savedExists && (!S_ISDIR(original.st_mode) || !WQSameObject(&original, &expected))) {
        errno = EINVAL;
        return NO;
    }

    BOOL cachesExists = fstatat(library, "Caches", &current, AT_SYMLINK_NOFOLLOW) == 0;
    if (!cachesExists && errno != ENOENT) return NO;

    if (savedExists) {
        if (cachesExists) {
            char link[65536];
            ssize_t length = S_ISLNK(current.st_mode)
                ? readlinkat(library, "Caches", link, sizeof(link) - 1) : -1;
            if (length < 0) { errno = EEXIST; return NO; }
            link[length] = 0;
            if (![record[@"Target"] isEqualToString:[NSString stringWithUTF8String:link]]) {
                errno = EEXIST;
                return NO;
            }
            if (unlinkat(library, "Caches", 0) != 0) return NO;
        }
        if (renameatx_np(library, WQCacheSaved, library, "Caches", RENAME_EXCL) != 0) return NO;
    } else if (!cachesExists || !S_ISDIR(current.st_mode) || !WQSameObject(&current, &expected)) {
        errno = EINVAL;
        return NO;
    }

    if (unlinkat(library, WQCacheMarker, 0) != 0) return NO;
    return fsync(library) == 0;
}

static BOOL WQCacheSwapBegin(int library, NSString *target)
{
    if (!WQCacheSwapRecover(library)) {
        // A leftover link / mismatched inode used to make every grant fail
        // forever (tried=[] last=-4). Repair first, then start the swap from
        // the clean folder it leaves behind.
        int recoverError = errno;
        NSString *state = WQCacheStateString(library);
        NSMutableArray<NSString *> *done = [NSMutableArray array];
        BOOL repaired = WQCacheSwapReset(library, done);
        NSLog(@"[worse_query] swap recovery failed errno=%d (%s) state=[%@]; reset %@%@",
              recoverError, strerror(recoverError), state,
              repaired ? @"ok" : @"FAILED",
              done.count ? [@": " stringByAppendingString:[done componentsJoinedByString:@", "]] : @"");
        if (!repaired) return NO;
    }
    struct stat st;
    if (fstatat(library, "Caches", &st, AT_SYMLINK_NOFOLLOW) != 0) {
        if (errno != ENOENT || mkdirat(library, "Caches", 0755) != 0 ||
            fstatat(library, "Caches", &st, AT_SYMLINK_NOFOLLOW) != 0) {
            NSLog(@"[worse_query] swap step Caches unavailable errno=%d (%s)",
                  errno, strerror(errno));
            return NO;
        }
    }
    if (!S_ISDIR(st.st_mode)) {
        NSLog(@"[worse_query] swap step Caches is not a folder");
        errno = EINVAL;
        return NO;
    }

    NSDictionary *record = @{
        @"Format": @1,
        @"Device": @(st.st_dev),
        @"Inode": @(st.st_ino),
        @"Target": target,
    };
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:record
                                                               format:NSPropertyListBinaryFormat_v1_0
                                                              options:0
                                                                error:nil];
    if (!data) { errno = EINVAL; return NO; }

    unlinkat(library, WQCacheMarkerTemp, 0);
    int marker = WQOpenRegularAt(library, WQCacheMarkerTemp, O_WRONLY | O_CREAT | O_EXCL, 0600);
    if (marker < 0) return NO;
    BOOL durable = WQWriteBytes(marker, data);
    if (close(marker) != 0) durable = NO;
    if (!durable) {
        unlinkat(library, WQCacheMarkerTemp, 0);
        return NO;
    }
    if (renameatx_np(library, WQCacheMarkerTemp, library, WQCacheMarker, RENAME_EXCL) != 0) {
        int err = errno;
        NSLog(@"[worse_query] swap step marker rename errno=%d (%s)", err, strerror(err));
        unlinkat(library, WQCacheMarkerTemp, 0);
        errno = err;
        return NO;
    }
    if (renameatx_np(library, "Caches", library, WQCacheSaved, RENAME_EXCL) != 0) {
        NSLog(@"[worse_query] swap step preserve Caches errno=%d (%s)", errno, strerror(errno));
        return NO;
    }
    if (symlinkat(target.fileSystemRepresentation, library, "Caches") != 0) {
        NSLog(@"[worse_query] swap step symlink -> %@ errno=%d (%s)",
              target, errno, strerror(errno));
        return NO;
    }
    return YES;
}

static BOOL WQRecoverCacheSwapAtPath(NSString *libraryPath)
{
    int library = WQOpenDirectoryNoLinks(libraryPath);
    if (library < 0) return errno == ENOENT;
    struct stat st;
    BOOL marker = fstatat(library, WQCacheMarker, &st, AT_SYMLINK_NOFOLLOW) == 0;
    int markerError = marker ? 0 : errno;
    BOOL saved = fstatat(library, WQCacheSaved, &st, AT_SYMLINK_NOFOLLOW) == 0;
    int savedError = saved ? 0 : errno;
    if ((!marker && markerError != ENOENT) || (!saved && savedError != ENOENT)) {
        close(library);
        return NO;
    }
    if (!marker && !saved) {
        close(library);
        return YES;
    }
    int lockfd = WQOpenRegularAt(library, WQCacheLock, O_RDWR | O_CREAT, 0600);
    BOOL ok = lockfd >= 0 && flock(lockfd, LOCK_EX | LOCK_NB) == 0 && WQCacheSwapRecover(library);
    int error = errno;
    if (lockfd >= 0) close(lockfd);
    close(library);
    if (!ok) errno = error;
    return ok;
}

// MARK: - App Group

NSString *worse_query_app_group(void)
{
    static SecTaskCreateFromSelfFn createTask;
    static SecTaskCopyEntitlementFn copyEntitlement;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY);
        if (!security) return;
        createTask = (SecTaskCreateFromSelfFn)dlsym(security, "SecTaskCreateFromSelf");
        copyEntitlement = (SecTaskCopyEntitlementFn)dlsym(security, "SecTaskCopyValueForEntitlement");
    });
    if (!createTask || !copyEntitlement) return nil;

    SecTaskRef task = createTask(kCFAllocatorDefault);
    if (!task) return nil;
    CFTypeRef value = copyEntitlement(task, CFSTR("com.apple.security.application-groups"), NULL);
    CFRelease(task);
    if (!value) return nil;

    NSMutableArray<NSString *> *groups = [NSMutableArray array];
    CFTypeID type = CFGetTypeID(value);
    if (type == CFArrayGetTypeID()) {
        for (id group in (__bridge NSArray *)value) {
            if ([group isKindOfClass:NSString.class] && [group length]) [groups addObject:group];
        }
    } else if (type == CFStringGetTypeID()) {
        NSString *group = (__bridge NSString *)value;
        if (group.length) [groups addObject:group];
    }
    CFRelease(value);

    NSFileManager *files = [NSFileManager defaultManager];
    for (NSString *group in groups) {
        if ([files containerURLForSecurityApplicationGroupIdentifier:group]) return group;
    }
    return nil;
}

BOOL worse_query_available(void)
{
    return worse_query_app_group() != nil;
}

// MARK: - Query

typedef struct {
    void *handle;
    cq_create_fn create;
    cq_set_u64_fn setClass;
    cq_set_u64_fn setFlags;
    cq_set_u64_fn setPart;
    cq_set_ids_fn setGroups;
    cq_result_fn single;
    cq_free_fn freeQuery;
    cq_token_fn copyToken;
    ext_consume_fn consume;
} WQQueryAPI;

static WQQueryAPI *WQQuery(void)
{
    static WQQueryAPI api;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        api.handle = dlopen("/usr/lib/system/libsystem_containermanager.dylib", RTLD_NOW | RTLD_LOCAL);
        if (!api.handle) return;
        api.create = (cq_create_fn)dlsym(api.handle, "container_query_create");
        api.setClass = (cq_set_u64_fn)dlsym(api.handle, "container_query_set_class");
        api.setGroups = (cq_set_ids_fn)dlsym(api.handle, "container_query_set_group_identifiers");
        api.setFlags = (cq_set_u64_fn)dlsym(api.handle, "container_query_operation_set_flags");
        api.setPart = (cq_set_u64_fn)dlsym(api.handle, "container_query_operation_set_part");
        api.single = (cq_result_fn)dlsym(api.handle, "container_query_get_single_result");
        api.freeQuery = (cq_free_fn)dlsym(api.handle, "container_query_free");
        api.copyToken = (cq_token_fn)dlsym(api.handle, "container_copy_sandbox_token");
        api.consume = (ext_consume_fn)dlsym(RTLD_DEFAULT, "sandbox_extension_consume");
    });
    if (!api.create || !api.setClass || !api.setGroups || !api.setFlags ||
        !api.setPart || !api.single || !api.freeQuery || !api.copyToken || !api.consume) {
        return NULL;
    }
    return &api;
}

// Flags candidate table (spec 02-00-ios27-grant-hardening, D-03.2): the two
// known-good values stay first to keep the exposure surface of unknown
// candidates minimal; the same-family bit-flips and a 0 fallback follow. If a
// 27.x build changes the flag semantics, the grant loop walks every candidate
// and heals the learned preference instead of dying after one flip.
static const uint64_t kWQFlagCandidates[] = {
    0x0000008000000000ULL,
    0x0000000800000000ULL,
    0x0000004000000000ULL,
    0x0000001000000000ULL,
    0x0000000000000000ULL,
};
static const int kWQFlagCandidateCount =
    (int)(sizeof(kWQFlagCandidates) / sizeof(kWQFlagCandidates[0]));

// Learned preference is keyed per OS major: a preference learned on 26.x must
// not pre-empt the version default on 27 (and vice versa). -1 = not learned.
static NSString *WQPreferredFlagsKeyForCurrentMajor(void)
{
    return [NSString stringWithFormat:@"wq.preferredQueryFlags.v%ld",
            (long)NSProcessInfo.processInfo.operatingSystemVersion.majorVersion];
}

static int WQPreferredFlags(void)
{
    NSString *key = WQPreferredFlagsKeyForCurrentMajor();
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    if ([value isKindOfClass:[NSNumber class]]) {
        int index = [value intValue];
        if (index >= 0 && index < kWQFlagCandidateCount) return index;
    }
    return -1;
}

static void WQSavePreferredFlags(int index)
{
    if (index < 0 || index >= kWQFlagCandidateCount) return;
    [[NSUserDefaults standardUserDefaults] setInteger:index
                                               forKey:WQPreferredFlagsKeyForCurrentMajor()];
}

static void WQClearPreferredFlags(void)
{
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:WQPreferredFlagsKeyForCurrentMajor()];
}

static int64_t WQQueryToken(NSString *group, int flagIndex)
{
    WQQueryAPI *api = WQQuery();
    if (!api) return -2;
    if (flagIndex < 0 || flagIndex >= kWQFlagCandidateCount) return -3;

    void *query = api->create();
    if (!query) return -3;

    int64_t handle = -5;
    char *token = NULL;
    xpc_object_t identifier = xpc_string_create(group.fileSystemRepresentation);
    api->setClass(query, 7); // app data / app group containers
    api->setGroups(query, identifier);
    api->setPart(query, 3);  // Library/Caches
    api->setFlags(query, kWQFlagCandidates[flagIndex]);
    // xpc_object_t is ARC-managed here; no explicit xpc_release.

    void *result = api->single(query);
    if (result) {
        token = api->copyToken(result);
        handle = token ? api->consume(token) : -6;
        if (token && handle < 0) handle = -7;
    }
    if (token) free(token);
    api->freeQuery(query);
    return handle;
}

// MARK: - Grant cache

static BOOL WQPathOpens(NSString *path)
{
    struct stat st;
    if (lstat(path.fileSystemRepresentation, &st) != 0) return NO;
    int flags = O_RDONLY | O_CLOEXEC | O_NONBLOCK;
    if (S_ISDIR(st.st_mode)) flags |= O_DIRECTORY;
    int fd = open(path.fileSystemRepresentation, flags);
    if (fd < 0) return NO;
    close(fd);
    return YES;
}

// Write-verification probe (spec 02-00-ios27-grant-hardening, D-03.3):
// confirms the sandbox token actually allows creating content in the target,
// so a read-only token can no longer fake a successful grant while every
// downstream write dies with EPERM. No payload bytes are ever written.
static BOOL WQPathWriteProbe(NSString *path)
{
    struct stat st;
    if (lstat(path.fileSystemRepresentation, &st) != 0) return NO;
    if (S_ISLNK(st.st_mode)) return NO; // unchanged lstat semantics: no symlink traversal

    if (S_ISDIR(st.st_mode)) {
        int dirfd = open(path.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
        if (dirfd < 0) return NO;
        // Probe file: random-suffixed name created O_CREAT|O_EXCL and
        // unlinked immediately. A leftover probe (unlink failure) rotates the
        // suffix on the next run; creation is attempted at most twice.
        BOOL writable = NO;
        for (int attempt = 0; attempt < 2 && !writable; attempt++) {
            char name[64];
            snprintf(name, sizeof(name), ".wq-write-probe-%d", arc4random_uniform(1000000));
            int pfd = openat(dirfd, name, O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC, 0600);
            if (pfd >= 0) {
                close(pfd);
                writable = YES;
                if (unlinkat(dirfd, name, 0) != 0) {
                    NSLog(@"[worse_query] probe cleanup failed name=%s errno=%d", name, errno);
                }
            } else if (errno != EEXIST) {
                // EACCES/EROFS/...: the token does not allow creating files here.
                break;
            }
            // EEXIST: name collision (unlikely with the random suffix); rotate.
        }
        close(dirfd);
        if (!writable) {
            NSLog(@"[worse_query] read-ok write-denied path=%@ errno=%d (%s)",
                  path, errno, strerror(errno));
        }
        return writable;
    }

    if (S_ISREG(st.st_mode)) {
        // Verify write access to an existing regular file WITHOUT truncating
        // or writing: open for write and immediately close.
        int fd = open(path.fileSystemRepresentation, O_WRONLY | O_CLOEXEC);
        if (fd < 0) {
            NSLog(@"[worse_query] read-ok write-denied path=%@ errno=%d (%s)",
                  path, errno, strerror(errno));
            return NO;
        }
        close(fd);
        return YES;
    }

    return NO;
}

// Combined verification for a freshly issued (or cached) token: readable
// always, plus the write probe when the caller declared a write requirement.
static BOOL WQTokenSatisfies(NSString *target, int require_write)
{
    if (!WQPathOpens(target)) return NO;
    if (!require_write) return YES;
    return WQPathWriteProbe(target);
}

static BOOL WQCacheGet(NSString *key, int64_t *handle)
{
    NSNumber *value = gWQCache[key];
    if (!value) return NO;
    [gWQOrder removeObject:key];
    [gWQOrder addObject:key];
    *handle = value.longLongValue;
    return YES;
}

static void WQCacheStore(NSString *key, int64_t handle)
{
    NSNumber *existing = gWQCache[key];
    if (existing) {
        WQReleaseToken(existing.longLongValue);
        [gWQOrder removeObject:key];
    }
    gWQCache[key] = @(handle);
    [gWQOrder addObject:key];
    while (gWQOrder.count > WQCacheLimit) {
        NSString *oldest = gWQOrder.firstObject;
        [gWQOrder removeObjectAtIndex:0];
        NSNumber *value = gWQCache[oldest];
        [gWQCache removeObjectForKey:oldest];
        if (value) WQReleaseToken(value.longLongValue);
    }
}

static NSString *WQNormalizeTarget(const char *rawPath)
{
    if (!rawPath || !rawPath[0]) return nil;
    NSString *path = [NSString stringWithUTF8String:rawPath];
    if (!path) return nil;
    while (path.length > 1 && [path hasSuffix:@"/"]) {
        path = [path substringToIndex:path.length - 1];
    }
    path = WQCanonicalVarPath(path);
    if (!WQAbsolutePathGrammar(path)) return nil;
    return path;
}

int64_t worse_query_grant_ex(const char *path, int require_write)
{
    NSString *target = WQNormalizeTarget(path);
    if (!target) return -1;

    // iOS 27 hardening (spec 02-00-ios27-grant-hardening, D-03.1): lstat is
    // no longer a hard gate. On tightened 27.x builds the sandbox may refuse
    // stat() on not-yet-granted paths, which made every grant die with -254
    // before the query even ran — an egg-and-chicken dead end. lstat only
    // saved a swap round-trip for nonexistent targets; the containermanagerd
    // validates the target itself, and a truly unreachable target is caught
    // by the WQPathOpens verification at the end (returns -8 instead).
    // Precedent: bad_query always skips lstat via create=true.
    struct stat st;
    if (lstat(target.fileSystemRepresentation, &st) != 0) {
        NSLog(@"[worse_query] lstat nonfatal path=%@ errno=%d (%s) — continuing to swap+query",
              target, errno, strerror(errno));
    }

    WQInit();
    [gWQLock lock];
    @try {
        int64_t cached = -1;
        if (WQCacheGet(target, &cached)) {
            // A cached token granted read-only is re-probed for write here:
            // if it fails the write requirement the entry is evicted and a
            // fresh token is queried below (design D-03.3).
            if (WQTokenSatisfies(target, require_write)) return cached;
            [gWQCache removeObjectForKey:target];
            [gWQOrder removeObject:target];
            WQReleaseToken(cached);
        }

        NSString *group = worse_query_app_group();
        if (!group) {
            NSLog(@"[worse_query] no App Group entitlement; re-sign with AltStore/SideStore/Sideloadly or an explicit App ID with App Groups");
            return -1;
        }
        NSURL *root = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:group];
        if (!root) return -1;

        NSString *libraryPath = [root.path stringByAppendingPathComponent:@"Library"];
        if (![[NSFileManager defaultManager] createDirectoryAtPath:libraryPath
                                       withIntermediateDirectories:YES
                                                        attributes:nil
                                                             error:nil]) {
            NSLog(@"[worse_query] cannot create %@", libraryPath);
            return -4;
        }

        int library = WQOpenDirectoryNoLinks(libraryPath);
        if (library < 0) return -4;
        int lockfd = WQOpenRegularAt(library, WQCacheLock, O_RDWR | O_CREAT, 0600);
        if (lockfd < 0) {
            close(library);
            return -4;
        }
        if (flock(lockfd, LOCK_EX) != 0) {
            close(lockfd);
            close(library);
            return -4;
        }

        BOOL swapped = NO;
        int swapError = 0;
        int64_t handle = -4;
        // Candidate walk (D-03.2): the learned preference for this OS major
        // goes first; without one, 27+ starts on the standard candidate and
        // 26.x on the alternative, matching the pre-hardening order. The walk
        // stays inside the swap window — outside it the query no longer
        // resolves to the target — and a failed preference self-heals into a
        // full pass over every candidate instead of dying after one flip.
        int preferred = WQPreferredFlags();
        int startIndex = preferred >= 0
            ? preferred
            : (NSProcessInfo.processInfo.operatingSystemVersion.majorVersion < 27 ? 1 : 0);
        int hitIndex = -1;
        NSMutableString *tried = [NSMutableString string];
        @try {
            swapped = WQCacheSwapBegin(library, target);
            if (!swapped) {
                swapError = errno ? errno : EIO;
                NSLog(@"[worse_query] access cache unavailable path=%@ errno=%d (%s) state=[%@]",
                      target, swapError, strerror(swapError), WQCacheStateString(library));
            }
            if (swapped) {
                for (int offset = 0; offset < kWQFlagCandidateCount && hitIndex < 0; offset++) {
                    int index = (startIndex + offset) % kWQFlagCandidateCount;
                    if (tried.length) [tried appendString:@","];
                    [tried appendFormat:@"%d", index];
                    int64_t candidate = WQQueryToken(group, index);
                    if (candidate >= 0) {
                        if (WQTokenSatisfies(target, require_write)) {
                            handle = candidate;
                            hitIndex = index;
                        } else {
                            // Issued but does not cover the target (wrong flag
                            // set, or read-only under require_write): drop it.
                            WQReleaseToken(candidate);
                            handle = -8;
                        }
                    } else {
                        // Keep the most recent failure code for attribution.
                        handle = candidate;
                    }
                }
                if (hitIndex < 0 && preferred >= 0) {
                    // The learned preference failed the full walk — clear it
                    // so the next grant starts from the version default.
                    WQClearPreferredFlags();
                }
            }
        } @finally {
            if (swapped) {
                if (!WQCacheSwapRecover(library)) {
                    NSLog(@"[worse_query] Caches recovery failed in %@ (errno=%d)", libraryPath, errno);
                }
            }
            flock(lockfd, LOCK_UN);
            close(lockfd);
            close(library);
        }

        if (!swapped) {
            // -5 = the access cache needs repair. Callers (SandboxAccess)
            // reset it once and retry; keep it distinct from a query miss so
            // the UI can point at "Reset Access Cache".
            return -5;
        }
        if (hitIndex < 0) {
            NSLog(@"[worse_query] no candidate satisfied verification path=%@ "
                  @"require_write=%d tried=[%@] last=%lld",
                  target, require_write, tried, (long long)handle);
            return handle;
        }
        WQSavePreferredFlags(hitIndex);
        WQCacheStore(target, handle);
        return handle;
    } @finally {
        [gWQLock unlock];
    }
}

int64_t worse_query_grant(const char *path)
{
    // Legacy read-only entry point: identical behavior to before the
    // grant_ex split (browsing, exports, and other read flows are unaffected
    // by the write probe).
    return worse_query_grant_ex(path, 0);
}

void worse_query_release(int64_t handle)
{
    if (handle < 0) return;
    WQInit();
    [gWQLock lock];
    BOOL cached = NO;
    for (NSNumber *value in gWQCache.allValues) {
        if (value.longLongValue == handle) { cached = YES; break; }
    }
    [gWQLock unlock];
    if (!cached) WQReleaseToken(handle);
}

void worse_query_forget_all(void)
{
    WQInit();
    [gWQLock lock];
    for (NSNumber *value in gWQCache.allValues) WQReleaseToken(value.longLongValue);
    [gWQCache removeAllObjects];
    [gWQOrder removeAllObjects];
    [gWQLock unlock];
}

BOOL worse_query_reset_access_cache(void)
{
    NSString *group = worse_query_app_group();
    if (!group) return NO;
    NSURL *root = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:group];
    if (!root) return NO;
    NSString *libraryPath = [root.path stringByAppendingPathComponent:@"Library"];
    [[NSFileManager defaultManager] createDirectoryAtPath:libraryPath
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    int library = WQOpenDirectoryNoLinks(libraryPath);
    if (library < 0) {
        NSLog(@"[worse_query] reset: cannot open %@ errno=%d (%s)",
              libraryPath, errno, strerror(errno));
        return NO;
    }
    NSMutableArray<NSString *> *done = [NSMutableArray array];
    int lockfd = WQCacheLockOpenForRepair(library, done);
    if (lockfd < 0 || flock(lockfd, LOCK_EX | LOCK_NB) != 0) {
        int err = errno;
        if (lockfd >= 0) close(lockfd);
        close(library);
        NSLog(@"[worse_query] reset: lock unavailable errno=%d (%s)%@",
              err, strerror(err),
              done.count ? [@"; " stringByAppendingString:[done componentsJoinedByString:@", "]] : @"");
        errno = err;
        return NO;
    }
    BOOL ok = WQCacheSwapReset(library, done);
    int err = errno;
    close(lockfd);
    close(library);
    NSLog(@"[worse_query] access cache reset in %@: %@%@",
          libraryPath,
          done.count ? [done componentsJoinedByString:@", "] : @"nothing to repair",
          ok ? @"" : [NSString stringWithFormat:@"; FAILED errno=%d (%s)", err, strerror(err)]);
    if (ok) {
        worse_query_invalidate_caches();
        errno = 0;
    } else {
        errno = err;
    }
    return ok;
}

BOOL worse_query_recover(void)
{
    NSString *group = worse_query_app_group();
    if (!group) return NO;
    NSURL *root = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:group];
    if (!root) return NO;
    BOOL ok = WQRecoverCacheSwapAtPath([root.path stringByAppendingPathComponent:@"Library"]);
    if (ok) return YES;
    int err = errno;
    NSLog(@"[worse_query] recovery needs repair errno=%d (%s); resetting access cache",
          err, strerror(err));
    BOOL repaired = worse_query_reset_access_cache();
    if (!repaired) errno = err;
    return repaired;
}

// MARK: - Container identifier index

static NSDictionary<NSString *, NSString *> *gPathIdentifiers;
static NSDictionary<NSString *, NSString *> *gIdentifierPaths;
static NSTimeInterval gIdentifierMapAt;

void worse_query_invalidate_caches(void)
{
    gPathIdentifiers = nil;
    gIdentifierPaths = nil;
    gIdentifierMapAt = 0;
}

static void WQBuildIdentifierMaps(void)
{
    NSMutableDictionary<NSString *, NSString *> *pathToID = [NSMutableDictionary new];
    NSMutableDictionary<NSString *, NSString *> *idToPath = [NSMutableDictionary new];

    void *mgr = dlopen("/usr/lib/system/libsystem_containermanager.dylib", RTLD_NOW | RTLD_LOCAL);
    if (!mgr) return;
    cq_create_fn create = (cq_create_fn)dlsym(mgr, "container_query_create");
    cq_set_u64_fn setClass = (cq_set_u64_fn)dlsym(mgr, "container_query_set_class");
    cq_iterate_fn iterate = (cq_iterate_fn)dlsym(mgr, "container_query_iterate_results_sync");
    cq_free_fn freeQuery = (cq_free_fn)dlsym(mgr, "container_query_free");
    co_get_path_fn getPath = (co_get_path_fn)dlsym(mgr, "container_object_get_path");
    co_get_id_fn getIdentifier = (co_get_id_fn)dlsym(mgr, "container_object_get_identifier");
    if (!getIdentifier) getIdentifier = (co_get_id_fn)dlsym(mgr, "container_result_get_identifier");
    if (!create || !setClass || !iterate || !freeQuery || !getPath || !getIdentifier) return;

    const uint64_t classes[] = { 0, 2, 5, 7, 8, 10, 11, 13 };
    for (size_t i = 0; i < sizeof(classes) / sizeof(classes[0]); i++) {
        void *query = create();
        if (!query) continue;
        setClass(query, classes[i]);
        __block NSUInteger accepted = 0;
        iterate(query, ^bool(void *object) {
            const char *rawPath = getPath(object);
            const char *rawIdentifier = getIdentifier(object);
            if (!rawPath || !rawIdentifier) return true;
            NSString *path = WQCanonicalVarPath([NSString stringWithUTF8String:rawPath]);
            NSString *identifier = [NSString stringWithUTF8String:rawIdentifier];
            if (!path.length || !identifier.length) return true;
            pathToID[path] = identifier;
            if (!idToPath[identifier]) idToPath[identifier] = path;
            accepted++;
            // Keep the first pass bounded; the index only needs known containers.
            return accepted < 4096;
        });
        freeQuery(query);
    }
    gPathIdentifiers = [pathToID copy];
    gIdentifierPaths = [idToPath copy];
    gIdentifierMapAt = NSDate.date.timeIntervalSinceReferenceDate;
}

NSDictionary<NSString *, NSString *> *worse_query_path_identifiers(void)
{
    WQInit();
    [gWQLock lock];
    NSTimeInterval now = NSDate.date.timeIntervalSinceReferenceDate;
    if (!gPathIdentifiers || now - gIdentifierMapAt > 60) WQBuildIdentifierMaps();
    NSDictionary *result = gPathIdentifiers ?: @{};
    [gWQLock unlock];
    return result;
}

NSDictionary<NSString *, NSString *> *worse_query_identifier_paths(void)
{
    WQInit();
    [gWQLock lock];
    NSTimeInterval now = NSDate.date.timeIntervalSinceReferenceDate;
    if (!gIdentifierPaths || now - gIdentifierMapAt > 60) WQBuildIdentifierMaps();
    NSDictionary *result = gIdentifierPaths ?: @{};
    [gWQLock unlock];
    return result;
}