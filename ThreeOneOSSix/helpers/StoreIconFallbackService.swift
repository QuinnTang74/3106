import Foundation
import UIKit

/// Store artwork fallback (WCMigrate's StoreIconLookup design; independent
/// implementation). When the local icon probe yields nothing (clone apps,
/// enterprise installs), query the iTunes lookup API by bundle ID and cache
/// the artwork URL in UserDefaults so later runs hit the network only when
/// the URL changes. Gated by a settings toggle; failures are silent — the
/// row simply keeps its placeholder glyph.
enum StoreIconFallbackService {

    static let enabledKey = "storeicon.fallback.enabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static func setEnabled(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: enabledKey)
    }

    private static var cacheURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("3106/store-icon-cache.plist")
    }

    /// actor: serializes lookups; in-memory image cache for the session.
    private actor Lookup {
        private var images: [String: UIImage] = [:]

        func cached(_ bundleID: String) -> UIImage? { images[bundleID] }
        func remember(_ image: UIImage?, for bundleID: String) {
            images[bundleID] = image
        }
    }

    private static let lookup = Lookup()

    /// Returns the store artwork for `bundleID`, or nil. Safe to call from
    /// any task; concurrent calls for the same ID coalesce on the actor.
    static func icon(for bundleID: String) async -> UIImage? {
        guard isEnabled, !bundleID.isEmpty else { return nil }
        if let memory = await lookup.cached(bundleID) { return memory }

        if let url = storedArtworkURL(for: bundleID) {
            if let image = await download(url) {
                await lookup.remember(image, for: bundleID)
                return image
            }
        }

        guard let remote = await lookupArtworkURL(bundleID) else { return nil }
        storeArtworkURL(remote, for: bundleID)
        guard let image = await download(remote) else { return nil }
        await lookup.remember(image, for: bundleID)
        return image
    }

    // MARK: - Lookup API

    private static func lookupArtworkURL(_ bundleID: String) async -> URL? {
        // The CN storefront hosts the WeChat-family listings the US store
        // may lack; try both, CN first (the app's primary audience).
        for country in ["cn", "us"] {
            var components = URLComponents(string: "https://itunes.apple.com/lookup")
            components?.queryItems = [
                URLQueryItem(name: "bundleId", value: bundleID),
                URLQueryItem(name: "country", value: country),
            ]
            guard let url = components?.url,
                  let (data, response) = try? await URLSession.shared.data(from: url),
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = payload["results"] as? [[String: Any]],
                  let first = results.first else { continue }
            if let big = first["artworkUrl512"] as? String, let parsed = URL(string: big) {
                return parsed
            }
            if let small = first["artworkUrl100"] as? String, let parsed = URL(string: small) {
                return parsed
            }
        }
        return nil
    }

    private static func download(_ url: URL) async -> UIImage? {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let image = UIImage(data: data) else { return nil }
        return image
    }

    // MARK: - URL cache

    private static func storedArtworkURL(for bundleID: String) -> URL? {
        guard let map = loadMap(), let raw = map[bundleID] else { return nil }
        return URL(string: raw)
    }

    private static func storeArtworkURL(_ url: URL, for bundleID: String) {
        var map = loadMap() ?? [:]
        map[bundleID] = url.absoluteString
        if let data = try? PropertyListEncoder().encode(map) {
            try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? data.write(to: cacheURL, options: .atomic)
        }
    }

    private static func loadMap() -> [String: String]? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? PropertyListDecoder().decode([String: String].self, from: data)
    }
}
