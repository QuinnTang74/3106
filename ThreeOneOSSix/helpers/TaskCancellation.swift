import Foundation

/// Cooperative cancellation for long operations (migrations, artwork
/// replacement, config-archive application). Generalizes the scan-only
/// ScanToken (Pathleak.swift) with a cancellation reason and registered
/// observers, without touching ScanToken itself.
final class CancellationToken {
    private let lock = NSLock()
    private var cancelled = false
    private var reason: String?
    private var handlers: [UUID: () -> Void] = [:]

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    /// Human-readable reason captured at cancel time (for diagnostics).
    var cancelReason: String? {
        lock.lock()
        defer { lock.unlock() }
        return reason
    }

    func cancel(reason: String = "user requested") {
        var fired: [() -> Void] = []
        lock.lock()
        if !cancelled {
            cancelled = true
            self.reason = reason
            fired = Array(handlers.values)
            handlers.removeAll()
        }
        lock.unlock()
        for handler in fired { handler() }
    }

    /// Register a handler fired once when the token is cancelled. Handlers
    /// are one-shot: the map is cleared when they fire, so no leak. Registering
    /// on an already-cancelled token fires immediately on the caller's thread
    /// — late registration must not silently drop a cleanup hook.
    @discardableResult
    func onCancel(_ handler: @escaping () -> Void) -> AnyObject {
        let id = UUID()
        var alreadyCancelled = false
        lock.lock()
        if cancelled {
            alreadyCancelled = true
        } else {
            handlers[id] = handler
        }
        lock.unlock()
        if alreadyCancelled {
            handler()
        }
        return CancelHandle()
    }

    /// Throws CancellationError when the token has been cancelled; the
    /// canonical per-chunk check inside long-running loops.
    func check() throws {
        if isCancelled { throw CancellationError() }
    }

    private final class CancelHandle {}
}
