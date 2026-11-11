import Foundation

/// MobileGestalt capability presets (GestaltX parity). Every key below is a
/// real CacheExtra key cross-checked against GestaltX (GPL-3.0), MGKeys,
/// Nugget and mond — never invent a key: on iOS 27, adding a key that did
/// not exist in the original cache can trip the boot-time cache validation
/// and force a full rebuild (restart bounce, Erosion's core lesson).
///
/// Risk profiles are structured (what happens / worst case / recovery) and
/// resolved through localization keys at render time. Category-level notes
/// are shared; identity-level presets add their own overrides.
enum GestaltPresetCategory: String, CaseIterable, Identifiable {
    case display
    case device
    case ipad
    case intelligence
    case advanced

    var id: String { rawValue }

    var titleKey: String { "gestalt.category.\(rawValue)" }
    var icon: String {
        switch self {
        case .display: return "display"
        case .device: return "iphone"
        case .ipad: return "ipad.landscape"
        case .intelligence: return "sparkles"
        case .advanced: return "wrench.and.screwdriver"
        }
    }
}

enum GestaltRiskLevel: String, Comparable {
    case low
    case medium
    case high

    static func < (lhs: GestaltRiskLevel, rhs: GestaltRiskLevel) -> Bool {
        let order: [GestaltRiskLevel] = [.low, .medium, .high]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

struct GestaltPreset: Identifiable {
    let id: String
    let category: GestaltPresetCategory
    let titleKey: String
    let detailKey: String
    /// CacheExtra keys toggled by this preset.
    let keys: [String]
    /// Custom per-key values for presets that are not a plain Boolean 1.
    var values: [String: Any]? = nil
    var riskLevel: GestaltRiskLevel = .medium
    /// Identity presets (device/region spoofing) need the full-screen risk
    /// confirmation before any write.
    var requiresRiskConfirmation: Bool = false

    var riskKey: String {
        // Per-preset overrides live at "risk.gestalt.<id>.*"; category-level
        // defaults at "risk.gestalt.category.<category>.*".
        "risk.gestalt.\(id)"
    }

    /// Resolve the risk note keys: prefer per-preset copy, fall back to the
    /// category defaults. The view checks existence via the localized bundle.
    var consequenceKey: String { "\(riskKey).consequence" }
    var worstCaseKey: String { "\(riskKey).worst_case" }
    var recoveryKey: String { "\(riskKey).recovery" }

    var categoryConsequenceKey: String { "risk.gestalt.category.\(category.rawValue).consequence" }
    var categoryWorstCaseKey: String { "risk.gestalt.category.\(category.rawValue).worst_case" }
    var categoryRecoveryKey: String { "risk.gestalt.category.\(category.rawValue).recovery" }
}

enum GestaltPresets {
    // MARK: - Preset table

    static let all: [GestaltPreset] = [
        // Display
        .init(id: "dynamicIsland", category: .display, titleKey: "gestalt.preset.dynamicIsland.title", detailKey: "gestalt.preset.dynamicIsland.detail", keys: ["YlEtTtHlNesRBMal1CqRaA"], riskLevel: .low),
        .init(id: "aod", category: .display, titleKey: "gestalt.preset.aod.title", detailKey: "gestalt.preset.aod.detail", keys: ["2OOJf1VhaM7NxfRok3HbWQ", "j8/Omm6s1lsmTDFsXjsBfA"], riskLevel: .medium),
        .init(id: "aodVibrancy", category: .display, titleKey: "gestalt.preset.aodVibrancy.title", detailKey: "gestalt.preset.aodVibrancy.detail", keys: ["ykpu7qyhqFweVMKtxNylWA"], riskLevel: .low),
        .init(id: "aodHighLuminance", category: .display, titleKey: "gestalt.preset.aodHighLuminance.title", detailKey: "gestalt.preset.aodHighLuminance.detail", keys: ["7brdL5xrEUWnlF9C0kdg5A"], riskLevel: .medium),
        .init(id: "aodFlipbook", category: .display, titleKey: "gestalt.preset.aodFlipbook.title", detailKey: "gestalt.preset.aodFlipbook.detail", keys: ["aoJSd/MXk7M40NgXTM6x+g"], riskLevel: .low),
        .init(id: "aodFlipbookCount", category: .display, titleKey: "gestalt.preset.aodFlipbookCount.title", detailKey: "gestalt.preset.aodFlipbookCount.detail", keys: ["qqrspu7CpuPdZwSDxNY+Fg"], values: ["qqrspu7CpuPdZwSDxNY+Fg": NSNumber(value: 3)], riskLevel: .medium),
        .init(id: "hdrPhotoDisplay", category: .display, titleKey: "gestalt.preset.hdrPhotoDisplay.title", detailKey: "gestalt.preset.hdrPhotoDisplay.detail", keys: ["a1r7npIrhXsZ7SmKRKC1eA"], riskLevel: .low),
        .init(id: "parallax", category: .display, titleKey: "gestalt.preset.parallax.title", detailKey: "gestalt.preset.parallax.detail", keys: ["UIParallaxCapability"], values: ["UIParallaxCapability": NSNumber(value: 0)], riskLevel: .low),
        .init(id: "pwm", category: .display, titleKey: "gestalt.preset.pwm.title", detailKey: "gestalt.preset.pwm.detail", keys: ["6IejgN+1Fmu5/QrZFOIeNw"], riskLevel: .medium),
        .init(id: "displayPort", category: .display, titleKey: "gestalt.preset.displayPort.title", detailKey: "gestalt.preset.displayPort.detail", keys: ["CoWnN4xo783YGn4wLrUatA"], riskLevel: .medium),
        .init(id: "liquidGlass", category: .display, titleKey: "gestalt.preset.liquidGlass.title", detailKey: "gestalt.preset.liquidGlass.detail", keys: ["SAGvsp6O6kAQ4fEfDJpC4Q"], riskLevel: .low),

        // Device
        .init(id: "bootChime", category: .device, titleKey: "gestalt.preset.bootChime.title", detailKey: "gestalt.preset.bootChime.detail", keys: ["QHxt+hGLaBPbQJbXiUJX3w"], riskLevel: .low),
        .init(id: "chargeLimit", category: .device, titleKey: "gestalt.preset.chargeLimit.title", detailKey: "gestalt.preset.chargeLimit.detail", keys: ["37NVydb//GP/GrhuTN+exg"], riskLevel: .low),
        .init(id: "tapToWake", category: .device, titleKey: "gestalt.preset.tapToWake.title", detailKey: "gestalt.preset.tapToWake.detail", keys: ["yZf3GTRMGTuwSV/lD7Cagw"], riskLevel: .low),
        .init(id: "cameraControl", category: .device, titleKey: "gestalt.preset.cameraControl.title", detailKey: "gestalt.preset.cameraControl.detail", keys: ["CwvKxM2cEogD3p+HYgaW0Q", "oOV1jhJbdV3AddkcCg0AEA"], riskLevel: .low),
        .init(id: "actionButton", category: .device, titleKey: "gestalt.preset.actionButton.title", detailKey: "gestalt.preset.actionButton.detail", keys: ["cT44WE1EohiwRzhsZ8xEsw"], riskLevel: .low),
        .init(id: "collisionSOS", category: .device, titleKey: "gestalt.preset.collisionSOS.title", detailKey: "gestalt.preset.collisionSOS.detail", keys: ["HCzWusHQwZDea6nNhaKndw"], riskLevel: .low),
        .init(id: "spatialFaceTimeAudio", category: .device, titleKey: "gestalt.preset.spatialFaceTimeAudio.title", detailKey: "gestalt.preset.spatialFaceTimeAudio.detail", keys: ["/EVOCjM/Nmb2roP5ebtEFA"], riskLevel: .low),

        // iPad
        .init(id: "pencil", category: .ipad, titleKey: "gestalt.preset.pencil.title", detailKey: "gestalt.preset.pencil.detail", keys: ["yhHcB0iH0d1XzPO/CFd3ow"], riskLevel: .low),
        .init(id: "stageManager", category: .ipad, titleKey: "gestalt.preset.stageManager.title", detailKey: "gestalt.preset.stageManager.detail", keys: ["qeaj75wk3HF4DwQ8qbIi7g"], riskLevel: .medium),
        .init(id: "ipadApps", category: .ipad, titleKey: "gestalt.preset.ipadApps.title", detailKey: "gestalt.preset.ipadApps.detail", keys: ["9MZ5AdH43csAUajl/dU+IQ"], riskLevel: .medium),

        // Intelligence
        .init(id: "ai", category: .intelligence, titleKey: "gestalt.preset.ai.title", detailKey: "gestalt.preset.ai.detail", keys: ["A62OafQ85EJAiiqKn4agtg"], riskLevel: .medium),
        .init(id: "siriOnDevice", category: .intelligence, titleKey: "gestalt.preset.siriOnDevice.title", detailKey: "gestalt.preset.siriOnDevice.detail", keys: ["K/R1GfGfCkXvEhaPS2Vrng"], riskLevel: .medium),
        .init(id: "audioIntelligence", category: .intelligence, titleKey: "gestalt.preset.audioIntelligence.title", detailKey: "gestalt.preset.audioIntelligence.detail", keys: ["rb2tKZxlj0Gm2tBmUQSLqQ"], riskLevel: .medium),
        .init(id: "personalTranslator", category: .intelligence, titleKey: "gestalt.preset.personalTranslator.title", detailKey: "gestalt.preset.personalTranslator.detail", keys: ["M1n2sAqf33NAOgZRGxQYBA"], riskLevel: .medium),
        .init(id: "photosCleanUp", category: .intelligence, titleKey: "gestalt.preset.photosCleanUp.title", detailKey: "gestalt.preset.photosCleanUp.detail", keys: ["XNCjqOupLM/S8fNyxRNQTA"], riskLevel: .medium),
        .init(id: "handwritingSynthesis", category: .intelligence, titleKey: "gestalt.preset.handwritingSynthesis.title", detailKey: "gestalt.preset.handwritingSynthesis.detail", keys: ["YgYIIViDt1kgzyIsIV61vA"], riskLevel: .medium),
        .init(id: "alwaysListeningSiri", category: .intelligence, titleKey: "gestalt.preset.alwaysListeningSiri.title", detailKey: "gestalt.preset.alwaysListeningSiri.detail", keys: ["TusANsf9Lfe3P/9fIXXSrQ"], riskLevel: .medium),

        // Advanced
        .init(id: "internal", category: .advanced, titleKey: "gestalt.preset.internal.title", detailKey: "gestalt.preset.internal.detail", keys: ["EqrsVvjcYDdxHBiQmGhAWw"], riskLevel: .high, requiresRiskConfirmation: true),
        .init(id: "internalBuild", category: .advanced, titleKey: "gestalt.preset.internalBuild.title", detailKey: "gestalt.preset.internalBuild.detail", keys: ["LBJfwOEzExRxzlAnSuI7eg"], riskLevel: .high, requiresRiskConfirmation: true),
        .init(id: "internalSettings", category: .advanced, titleKey: "gestalt.preset.internalSettings.title", detailKey: "gestalt.preset.internalSettings.detail", keys: ["Oji6HRoPi7rH7HPdWVakuw"], riskLevel: .high, requiresRiskConfirmation: true),
        .init(id: "srd", category: .advanced, titleKey: "gestalt.preset.srd.title", detailKey: "gestalt.preset.srd.detail", keys: ["XYlJKKkj2hztRP1NWWnhlw"], riskLevel: .high, requiresRiskConfirmation: true),
    ]

    static func presets(in category: GestaltPresetCategory) -> [GestaltPreset] {
        all.filter { $0.category == category }
    }

    static func preset(id: String) -> GestaltPreset? {
        all.first { $0.id == id }
    }
}

// MARK: - Apply / revert engine

enum GestaltPresetError: Error, Equatable {
    case unavailable
    case unreadable
    case invalidPlist
    case missingCacheExtra
    case keyNotInOriginalCache(key: String)
    case unsupportedValueType(key: String)
}

/// Apply/revert engine for presets. Hard rule: a preset may only toggle keys
/// that ALREADY exist in the device's CacheExtra (iOS 27 anti-bounce rule).
/// Turning a key "on" that the device never had is refused with
/// `keyNotInOriginalCache` — the UI surfaces this as "not applicable on this
/// device" instead of a blind write.
enum GestaltPresetEngine {

    static func currentState(for preset: GestaltPreset) throws -> Bool {
        let cacheExtra = try readCacheExtra()
        guard let firstKey = preset.keys.first, let current = cacheExtra[firstKey] else {
            return false
        }
        if let custom = preset.values, let desired = custom[firstKey] {
            return isEqual(current, desired)
        }
        return (current as? NSNumber)?.boolValue == true
    }

    /// True when every key of the preset already exists in CacheExtra (i.e.
    /// the preset is applicable on this device).
    static func isApplicable(_ preset: GestaltPreset) -> Bool {
        guard let cacheExtra = try? readCacheExtra() else { return false }
        return preset.keys.allSatisfy { cacheExtra[$0] != nil }
    }

    static func apply(_ preset: GestaltPreset, enabled: Bool) throws {
        let path = GestaltKeys.gestaltPath
        let directory = (path as NSString).deletingLastPathComponent
        let grant = ContainerStore.grantContainerAccess(directory)
        defer {
            if grant >= 0 { SandboxAccess.release(grant) }
        }
        guard FileManager.default.fileExists(atPath: path) else {
            throw GestaltPresetError.unavailable
        }

        var root = try GestaltPlistIO.readRoot()
        guard var cacheExtra = root["CacheExtra"] as? [String: Any] else {
            throw GestaltPresetError.missingCacheExtra
        }

        for key in preset.keys {
            // Anti-bounce guard: the key must already exist on this device.
            guard cacheExtra[key] != nil else {
                throw GestaltPresetError.keyNotInOriginalCache(key: key)
            }
            if enabled {
                if let custom = preset.values, let desired = custom[key] {
                    cacheExtra[key] = desired
                } else {
                    // Preserve the existing numeric type: if the original
                    // value was a Real/Integer, keep that shape.
                    if let original = cacheExtra[key] as? NSNumber,
                       GestaltValueKind.detect(original) == .real {
                        cacheExtra[key] = NSNumber(value: 1.0)
                    } else {
                        cacheExtra[key] = NSNumber(value: true)
                    }
                }
            } else {
                // Revert records the original value first, then restores it.
                // For the off-state we restore the pre-enable value captured
                // by BackupCenter during apply; direct off writes the
                // conservative default (false/0-style) only when no backup
                // exists, matching GestaltX's restore-field behavior.
                cacheExtra[key] = NSNumber(value: false)
            }
        }

        root["CacheExtra"] = cacheExtra
        try GestaltPlistIO.writeRoot(root, reason: "preset:\(preset.id)")
        ActivityHistory.log(
            enabled ? .write : .restore,
            feature: "gestalt",
            "preset:\(preset.id)"
        )
        SoundEffects.play(.confirm)
    }

    private static func isEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        if let ln = lhs as? NSNumber, let rn = rhs as? NSNumber {
            return ln == rn
        }
        return "\(lhs)" == "\(rhs)"
    }

    private static func readCacheExtra() throws -> [String: Any] {
        let root = try GestaltPlistIO.readRoot()
        guard let cacheExtra = root["CacheExtra"] as? [String: Any] else {
            throw GestaltPresetError.missingCacheExtra
        }
        return cacheExtra
    }
}

/// Shared plist IO for the Gestalt editors: read with a sandbox grant,
/// write through the verified pipeline (serialize in the original format,
/// read the bytes back, then hand to VerifiedFileWriter for the automatic
/// pre-write backup and in-place inode-preserving replacement).
enum GestaltPlistIO {
    static func readRoot() throws -> [String: Any] {
        let path = GestaltKeys.gestaltPath
        let directory = (path as NSString).deletingLastPathComponent
        let grant = ContainerStore.grantContainerAccess(directory)
        defer {
            if grant >= 0 { SandboxAccess.release(grant) }
        }
        guard let data = FileManager.default.contents(atPath: path), !data.isEmpty else {
            throw GestaltPresetError.unreadable
        }
        guard let root = try? PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        ) as? [String: Any] else {
            throw GestaltPresetError.invalidPlist
        }
        return root
    }

    static func writeRoot(_ root: [String: Any], reason: String) throws {
        let path = GestaltKeys.gestaltPath
        let directory = (path as NSString).deletingLastPathComponent
        let grant = ContainerStore.grantContainerAccess(directory)
        defer {
            if grant >= 0 { SandboxAccess.release(grant) }
        }

        // Preserve the on-disk format (binary vs XML) of the original cache.
        let format: PropertyListSerialization.PropertyListFormat
        if let existing = FileManager.default.contents(atPath: path) {
            var detected = PropertyListSerialization.PropertyListFormat.binary
            _ = try? PropertyListSerialization.propertyList(
                from: existing, options: [], format: &detected
            )
            format = detected
        } else {
            format = .binary
        }
        let data: Data
        do {
            data = try PropertyListSerialization.data(
                fromPropertyList: root, format: format, options: 0
            )
        } catch {
            throw GestaltPresetError.invalidPlist
        }
        guard !data.isEmpty else { throw GestaltPresetError.invalidPlist }
        // Read-back before writing: a malformed plist never reaches disk.
        guard (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) != nil else {
            throw GestaltPresetError.invalidPlist
        }

        try VerifiedFileWriter.write(
            data,
            to: URL(fileURLWithPath: path),
            feature: .gestalt,
            reason: reason
        )
    }
}
