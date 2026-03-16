import Foundation
import Network

// MARK: - NetworkMonitor

/// Observes device connectivity using NWPathMonitor.
/// Publishes connectivity state changes via @Published properties (updated on the main actor).
final class NetworkMonitor: ObservableObject, @unchecked Sendable {

    // MARK: - Published State

    @MainActor @Published private(set) var isOnline: Bool = true
    @MainActor @Published private(set) var connectionType: ConnectionType = .unknown

    enum ConnectionType: String, Sendable {
        case wifi
        case cellular
        case wired
        case unknown
    }

    // MARK: - Private

    private let monitor: NWPathMonitor
    private let queue: DispatchQueue

    // MARK: - Init

    nonisolated init() {
        self.monitor = NWPathMonitor()
        self.queue = DispatchQueue(label: "com.pharmaapp.networkmonitor", qos: .utility)
    }

    // MARK: - Lifecycle

    @MainActor
    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasOnline = self.isOnline
                self.isOnline = path.status == .satisfied
                self.connectionType = Self.resolveConnectionType(path)
                if !wasOnline && self.isOnline {
                    NotificationCenter.default.post(
                        name: .networkDidBecomeAvailable,
                        object: nil
                    )
                }
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }

    // MARK: - Observation

    /// Returns an AsyncStream that yields each time the device transitions from offline → online.
    nonisolated func onConnectivityRestored() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let observer = NotificationCenter.default.addObserver(
                forName: .networkDidBecomeAvailable,
                object: nil,
                queue: .main
            ) { _ in
                continuation.yield(())
            }
            continuation.onTermination = { _ in
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }

    // MARK: - Helpers

    nonisolated private static func resolveConnectionType(_ path: NWPath) -> ConnectionType {
        if path.usesInterfaceType(.wifi) { return .wifi }
        if path.usesInterfaceType(.cellular) { return .cellular }
        if path.usesInterfaceType(.wiredEthernet) { return .wired }
        return .unknown
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let networkDidBecomeAvailable = Notification.Name("NetworkMonitor.networkDidBecomeAvailable")
}
