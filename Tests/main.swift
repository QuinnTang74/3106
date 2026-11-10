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

if failures == 0 {
    print("PASS: \(checks) policy checks")
    exit(0)
} else {
    print("FAILED: \(failures)/\(checks) checks")
    exit(1)
}