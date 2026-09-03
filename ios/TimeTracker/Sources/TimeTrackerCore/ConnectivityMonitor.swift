import Foundation
import Network

@MainActor
@Observable
public final class ConnectivityMonitor {
    public private(set) var isConnected = false
    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.timetracker.connectivity")

    public init() {
        monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
