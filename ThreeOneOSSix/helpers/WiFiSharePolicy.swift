import Foundation
import Security

/// Pure rules behind the Wi-Fi transfer server: authentication, path
/// containment, upload naming and port selection.
///
/// Kept free of `Network` so every one of these can be tested without binding a
/// socket. Each rule here protects against a specific, realistic mistake:
/// serving a file outside the container, letting two uploads race onto one
/// path, or accepting a request because the comparison was short-circuited.
enum WiFiSharePolicy {
    static let username = "3106"
    static let realm = "3106 Wi-Fi Transfer"

    /// Ports the listener tries in order. One entitlement-free port is not
    /// enough: AirPlay, printers and other LAN services squat on 8080 often
    /// enough that a single-port design fails intermittently.
    static let portRange = Array(8080...8090)

    // MARK: - PIN

    /// Six decimal digits from the system CSPRNG. `Int.random` would also be
    /// fine for a LAN-only code, but the PIN is the only thing standing between
    /// a stranger on the same Wi-Fi network and the user's container, so it
    /// uses `SecRandomCopyBytes`.
    ///
    /// Uniform by rejection: `2^32 % 10 != 0`, so plain `% 10` would favour the
    /// low digits slightly. Rejecting the tail costs one extra draw in ~2 of
    /// every 10^9 calls.
    static func generatePIN(uniform: () -> UInt32 = { secureRandom(count: 4) }) -> String {
        var out = ""
        // 0xFFFFFFF6 is the largest multiple of 10 ≤ UInt32.max.
        let limit: UInt32 = UInt32.max - (UInt32.max % 10)
        while out.count < 6 {
            let raw = uniform()
            guard raw < limit else { continue }
            out.append("\((raw % 10))")
        }
        return out
    }

    /// One 32-bit draw from the system CSPRNG. `count` is the byte count and is
    /// fixed at 4 by the only caller; it stays a parameter so the unsafe buffer
    /// size is explicit rather than a literal buried in a call.
    static func secureRandom(count: Int) -> UInt32 {
        precondition(count == MemoryLayout<UInt32>.size, "draws are 32-bit")
        var value: UInt32 = 0
        let status = withUnsafeMutableBytes(of: &value) { buffer in
            SecRandomCopyBytes(kSecRandomDefault, count, buffer.baseAddress!)
        }
        // A CSPRNG failure must not silently produce a predictable PIN.
        if status != errSecSuccess {
            assertionFailure("SecRandomCopyBytes failed with status \(status)")
        }
        return value
    }

    // MARK: - Authentication

    /// The exact header value a correct client sends.
    static func expectedAuthorization(pin: String) -> String {
        let raw = "\(username):\(pin)"
        return "Basic " + Data(raw.utf8).base64EncodedString()
    }

    /// Constant-time over the header: comparing with `==` on a secret lets a
    /// local attacker time the response and recover the PIN digit by digit.
    static func isAuthorized(header: String?, pin: String) -> Bool {
        guard let header else { return false }
        let expected = expectedAuthorization(pin: pin)
        guard header.count == expected.count else { return false }
        var diff: UInt8 = 0
        for (a, b) in zip(header.utf8, expected.utf8) {
            diff |= a ^ b
        }
        return diff == 0
    }

    // MARK: - Path containment

    /// Percent-decodes and resolves a request path against a root, refusing
    /// anything that escapes it.
    ///
    /// `..` is rejected outright rather than resolved: resolving then comparing
    /// prefixes is the classic TOCTOU shape, and no legitimate request needs a
    /// traversal segment.
    static func containedPath(_ requested: String, within root: URL) -> URL? {
        let decoded = requested.removingPercentEncoding ?? requested
        guard !decoded.contains("..") else { return nil }
        guard !decoded.contains("\0") else { return nil }
        guard decoded.hasPrefix("/") else { return nil }

        let rootPath = root.standardizedFileURL.path
        let candidate = root.appendingPathComponent(String(decoded.dropFirst()))
            .standardizedFileURL
        let candidatePath = candidate.path
        guard candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/") else {
            return nil
        }
        return candidate
    }

    // MARK: - Upload naming

    /// `report.txt` → `report 2.txt` → `report 3.txt`. Never overwrites: an
    /// upload onto an existing name is far more often a mistake than an intent.
    static func uniqueDestination(for name: String, existing: (String) -> Bool) -> String {
        guard existing(name) else { return name }

        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        var index = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            if !existing(candidate) { return candidate }
            index += 1
            if index > 9999 { return candidate }   // pathological; give up climbing
        }
    }

    // MARK: - Body size

    /// Directory archives are capped: a LAN transfer of multi-GB data through a
    /// phone's memory is not something this server should attempt.
    static let maximumZipBytes = 2 * 1024 * 1024 * 1024

    /// Upload chunk size. The body is streamed to a `.part` file rather than
    /// buffered, so this is an I/O granularity, not a memory bound.
    static let uploadChunkBytes = 64 * 1024

    // MARK: - Request line

    struct RequestLine: Equatable {
        let method: String
        let target: String     // path plus optional query, percent-encoded
        let path: String       // path only
        let query: String      // query only, empty when absent
    }

    /// `GET /api/download?path=a%2Fb.txt HTTP/1.1`.
    ///
    /// Only the first token matters for routing, but the target is split so
    /// callers never hand a query string to the containment check.
    static func parseRequestLine(_ line: String) -> RequestLine? {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0]).uppercased()
        let target = String(parts[1])
        guard target.hasPrefix("/") else { return nil }
        let split = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        return RequestLine(
            method: method,
            target: target,
            path: split[0].description,
            query: split.count > 1 ? split[1].description : ""
        )
    }

    /// Percent-decodes one query parameter. Returns nil when absent.
    static func queryParameter(_ name: String, in query: String) -> String? {
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0] == Substring(name) else { continue }
            return String(parts[1]).removingPercentEncoding ?? String(parts[1])
        }
        return nil
    }

    /// Extracts the `Authorization` value from raw header text.
    static func authorizationHeader(in headers: String) -> String? {
        for line in headers.split(separator: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "authorization"
            else { continue }
            return parts[1].trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    static func contentLength(in headers: String) -> Int? {
        for line in headers.split(separator: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length"
            else { continue }
            return Int(parts[1].trimmingCharacters(in: .whitespaces))
        }
        return nil
    }
}