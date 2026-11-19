import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Chip-family detection for the one capability decision that depends on
/// silicon rather than iOS version.
///
/// `CPUFAMILY_ARM_HURRICANE` (= A10 Fusion, used by iPhone 7 and iPad 6/7)
/// hangs inside the kernel chain on iOS 17. Every other supported chip family
/// runs it fine, so this must stay narrowly scoped to "is this an A10" rather
/// than any broader capability gate.
enum DeviceCPU {
    /// Read once: `SandboxAccess.backend` is a computed property consulted on
    /// every grant, and the chip cannot change at runtime.
    ///
    /// `hw.cpufamily` is 32-bit. Reading it needs no entitlement and does not
    /// leak anything more specific than the chip family.
    static let cpuFamily: Int32? = {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("hw.cpufamily", &value, &size, nil, 0) == 0, size > 0 else {
            return nil
        }
        return value
    }()

    /// A10 Fusion (`CPUFAMILY_ARM_HURRICANE`). The constant lives in
    /// `mach/machine.h`; the value matches `kexploit/machine_info.h` and
    /// Apple's header: `0x67CEEE93`.
    static let a10Family: Int32 = 0x67CEEE93

    /// A8 (`CPUFAMILY_ARM_TYPHOON`). Kept for tests so a regression that
    /// swaps the two literals fails instead of silently disabling the guard.
    static let typhoonFamily: Int32 = 0x2C91A47E

    static var isA10: Bool {
        cpuFamily == a10Family
    }

    /// Pure: tests must not depend on the host machine's chip.
    static func isA10(family: Int32?) -> Bool {
        family == a10Family
    }
}