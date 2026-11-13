import Foundation

enum AppUpdateChecker {
    static let dismissedVersionKey = "update.dismissedVersion"
    static let lastForegroundCheckKey = "update.lastForegroundCheck"
    /// Foreground checks are throttled so every app-switch does not hit the
    /// unauthenticated API (60 req/h per IP); 30 minutes matches the typical
    /// session-cadence a user needs to learn about a fresh release.
    static let foregroundThrottleInterval: TimeInterval = 30 * 60
    // Points at the 3106 fork; a missing repository simply disables update
    // prompts until the final distribution address is provided.
    static let apiURL = URL(string: "https://api.github.com/repos/QuinnTang74/3106/releases/latest")!
    static let fallbackURL = URL(string: "https://github.com/QuinnTang74/3106/releases/latest")!

    struct Offer: Identifiable {
        let id = UUID()
        let version: String
        let url: URL
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "AppReleaseDisplayVersion") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0"
    }

    static func dismiss(version: String) {
        UserDefaults.standard.set(version, forKey: dismissedVersionKey)
    }

    /// Manual-check variant: same probe, but a version the user previously
    /// dismissed still surfaces (they asked, so tell them).
    static func checkIgnoringDismissal() async -> Offer? {
        guard let offer = await check() else {
            // check() suppresses dismissed versions; re-probe raw and
            // compare versions directly.
            var request = URLRequest(url: apiURL)
            request.timeoutInterval = 15
            request.setValue("3106", forHTTPHeaderField: "User-Agent")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            guard
                let (data, _) = try? await URLSession.shared.data(for: request),
                let decoded = try? JSONDecoder().decode(GitHubRelease.self, from: data),
                isNewer(normalize(decoded.tagName), than: currentVersion)
            else { return nil }
            return Offer(
                version: normalize(decoded.tagName),
                url: URL(string: decoded.htmlURL) ?? fallbackURL
            )
        }
        return offer
    }

    // MARK: - Outcomes with reasons (3.2.4)

    /// What a manual check found, INCLUDING why it found nothing. The
    /// settings page renders each case distinctly — "already latest" and
    /// "the probe itself failed" must not collapse into one line.
    enum CheckOutcome {
        case upToDate
        case updateAvailable(Offer)
        /// Network/API failure with a human-readable reason (already
        /// localized by the caller via these keys).
        case failure(FailureReason)
    }

    enum FailureReason: Equatable {
        /// No reachable network interface (URLError, not an HTTP status).
        case offline
        /// API answered with a non-2xx status (rate limit, server error).
        case httpStatus(Int)
        /// Response arrived but could not be parsed.
        case badResponse
        /// Something else; carries a diagnostic string for the log.
        case other(String)

        var localizationKey: String {
            switch self {
            case .offline: return "update.failure.offline"
            case .httpStatus: return "update.failure.http"
            case .badResponse: return "update.failure.bad_response"
            case .other: return "update.failure.other"
            }
        }
    }

    /// Manual check with explicit outcome — the settings page uses this so
    /// a blocked probe shows WHY instead of a false "you are up to date".
    static func checkWithOutcome() async -> CheckOutcome {
        var request = URLRequest(url: apiURL)
        request.timeoutInterval = 15
        request.setValue("3106", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            // URLError codes that mean "no usable path to the host".
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost,
                 .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
                 .timedOut, .internationalRoamingOff, .dataNotAllowed:
                return .failure(.offline)
            default:
                return .failure(.other(error.localizedDescription))
            }
        } catch {
            return .failure(.other(error.localizedDescription))
        }
        guard let http = response as? HTTPURLResponse else {
            return .failure(.badResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            return .failure(.httpStatus(http.statusCode))
        }
        guard let decoded = try? JSONDecoder().decode(GitHubRelease.self, from: data) else {
            return .failure(.badResponse)
        }
        let remote = normalize(decoded.tagName)
        guard !remote.isEmpty else {
            return .failure(.badResponse)
        }
        if isNewer(remote, than: currentVersion) {
            let url = URL(string: decoded.htmlURL) ?? fallbackURL
            return .updateAvailable(Offer(version: remote, url: url))
        }
        return .upToDate
    }

    /// Foreground-switch check with a 30-minute throttle, persisted in
    /// UserDefaults so app relaunches within the window also stay quiet
    /// (the onAppear cold-start check remains unconditional). Offers fire
    /// the same alert as the cold-start path; failures are silent here.
    static func throttledForegroundCheck() async -> Offer? {
        let now = Date().timeIntervalSince1970
        let last = UserDefaults.standard.double(forKey: lastForegroundCheckKey)
        guard now - last >= foregroundThrottleInterval else { return nil }
        UserDefaults.standard.set(now, forKey: lastForegroundCheckKey)
        return await check()
    }

    static func check() async -> Offer? {
        var request = URLRequest(url: apiURL)
        request.timeoutInterval = 15
        request.setValue("3106", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            let decoded = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let remote = normalize(decoded.tagName)
            guard !remote.isEmpty,
                  isNewer(remote, than: currentVersion),
                  UserDefaults.standard.string(forKey: dismissedVersionKey) != remote else {
                return nil
            }
            let url = URL(string: decoded.htmlURL) ?? fallbackURL
            return Offer(version: remote, url: url)
        } catch {
            return nil
        }
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let htmlURL: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    static func normalize(_ version: String) -> String {
        var value = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("v") {
            value.removeFirst()
        }
        return value
    }

    static func isNewer(_ remote: String, than local: String) -> Bool {
        let remoteParts = numericParts(normalize(remote))
        let localParts = numericParts(normalize(local))
        let count = max(remoteParts.count, localParts.count)
        for i in 0..<count {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let l = i < localParts.count ? localParts[i] : 0
            if r != l { return r > l }
        }
        return false
    }

    private static func numericParts(_ version: String) -> [Int] {
        let core = version.split(separator: "-").first.map(String.init) ?? version
        return core.split(separator: ".").compactMap { Int($0.filter(\.isNumber)) }
    }
}
