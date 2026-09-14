import Foundation
#if canImport(Network)
import Network
#endif

/// Knows whether a new decision is even possible right now, so the app can say so
/// up front instead of failing halfway through.
///
/// Wrapped behind `canImport(Network)` so the decision pipeline can be compiled
/// and tested on any platform, not only Apple's.
public final class Reachability: @unchecked Sendable {
    public static let shared = Reachability()

    private let lock = NSLock()
    private var _isConnected = true

    public var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isConnected
    }

    #if canImport(Network)
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.decide.reachability")
    #endif

    private init() {
        #if canImport(Network)
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            lock.lock()
            _isConnected = path.status == .satisfied
            lock.unlock()
        }
        monitor.start(queue: queue)
        #endif
    }
}
