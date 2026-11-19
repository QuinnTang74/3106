import Foundation
import Network
import Combine

/// LAN file transfer over plain HTTP — the phone serves its Documents folder to
/// a browser on the same Wi-Fi, and accepts uploads back.
///
/// Design constraints that shaped this:
/// - **No entitlement beyond local network.** Nothing here touches the sandbox
///   escape; it serves the app's own Documents directory, so it works on every
///   supported OS version including ones that currently have no container
///   access at all.
/// - **Basic Auth over LAN only.** HTTPS would need a certificate the browser
///   trusts, which on a local IP means a manual trust dance. A 6-digit PIN with
///   constant-time comparison is the proportionate answer to "someone else on
///   this network can open a socket".
/// - **Never overwrite.** An upload colliding with an existing name is almost
///   always a mistake, so names climb `name 2.ext`, `name 3.ext`.
/// - **Streaming.** Upload bodies and ZIP responses both go through files, not
///   memory: a 2 GB archive held in RAM would kill the app.
@MainActor
final class WiFiShareServer: ObservableObject {
    enum State: Equatable {
        case stopped
        case starting
        case running(port: UInt16, address: String)
        case failed(String)
    }

    @Published private(set) var state: State = .stopped
    @Published private(set) var pin: String = ""
    @Published private(set) var activeConnections: Int = 0
    /// Recent request lines, newest first — the only diagnostics a user can act
    /// on when the browser shows a blank page.
    @Published private(set) var recentRequests: [String] = []

    /// Documents/3106/Transfer. A dedicated folder keeps a stray upload from
    /// landing next to the app's own state files.
    let rootURL: URL

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "wifi.share.server", qos: .userInitiated)
    private var connections: [ObjectIdentifier: WiFiShareConnection] = [:]

    init(rootURL: URL? = nil) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        self.rootURL = rootURL ?? docs
            .appendingPathComponent("3106", isDirectory: true)
            .appendingPathComponent("Transfer", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.rootURL, withIntermediateDirectories: true)
    }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    // MARK: - Start / stop

    func start() {
        guard !isRunning else { return }
        state = .starting
        // A fresh PIN per session: a code that survived relaunch would let
        // yesterday's screenshot keep working today.
        pin = WiFiSharePolicy.generatePIN()

        let address = Self.localIPv4Address() ?? "127.0.0.1"
        tryListen(portIndex: 0, address: address)
    }

    private func tryListen(portIndex: Int, address: String) {
        guard portIndex < WiFiSharePolicy.portRange.count else {
            state = .failed("No free port in 8080–8090")
            return
        }
        let port = NWEndpoint.Port(rawValue: UInt16(WiFiSharePolicy.portRange[portIndex]))!
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        // loopback is intentionally included: the Simulator and a same-device
        // browser would otherwise both need the Wi-Fi interface.
        parameters.includePeerToPeer = false

        let listener: NWListener
        do {
            listener = try NWListener(using: parameters, on: port)
        } catch {
            tryListen(portIndex: portIndex + 1, address: address)
            return
        }
        self.listener = listener

        listener.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }
            Task { @MainActor in
                switch newState {
                case .ready:
                    self.state = .running(port: UInt16(WiFiSharePolicy.portRange[portIndex]),
                                          address: address)
                case .failed(let error):
                    self.listener?.cancel()
                    self.listener = nil
                    self.tryListen(portIndex: portIndex + 1, address: address)
                    _ = error
                case .cancelled:
                    if case .running = self.state { self.state = .stopped }
                default:
                    break
                }
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            Task { @MainActor in
                self.accept(connection)
            }
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
        activeConnections = 0
        state = .stopped
    }

    // MARK: - Connection handling

    private func accept(_ connection: NWConnection) {
        activeConnections += 1
        let handler = WiFiShareConnection(
            connection: connection,
            rootURL: rootURL,
            pin: pin,
            onRequest: { [weak self] line in
                Task { @MainActor in self?.noteRequest(line) }
            },
            onFinish: { [weak self] id in
                Task { @MainActor in self?.finish(id) }
            }
        )
        connections[ObjectIdentifier(handler)] = handler
        handler.start(on: queue)
    }

    private func noteRequest(_ line: String) {
        recentRequests.insert(line, at: 0)
        if recentRequests.count > 20 { recentRequests.removeLast() }
    }

    private func finish(_ id: ObjectIdentifier) {
        connections.removeValue(forKey: id)
        activeConnections = max(0, activeConnections - 1)
    }

    // MARK: - Address

    /// Best-effort IPv4 of the Wi-Fi interface, for the URL shown on screen.
    /// Falls back to nil rather than guessing: showing a stale address is worse
    /// than showing none, because the user will type it and get a timeout.
    nonisolated static func localIPv4Address() -> String? {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return nil }
        defer { freeifaddrs(pointer) }

        var result: String?
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(entry.pointee.ifa_flags)
            guard flags & IFF_UP == IFF_UP,
                  flags & IFF_LOOPBACK == 0,
                  entry.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let status = getnameinfo(
                entry.pointee.ifa_addr,
                socklen_t(entry.pointee.ifa_addr.pointee.sa_len),
                &host, socklen_t(host.count),
                nil, 0,
                NI_NUMERICHOST
            )
            guard status == 0 else { continue }
            let name = String(cString: entry.pointee.ifa_name)
            // en0 is Wi-Fi on iPhone; anything else may be a tunnel (utun) or
            // the cellular interface, which the browser cannot reach.
            guard name.hasPrefix("en") else { continue }
            result = String(cString: host)
            break
        }
        return result
    }
}