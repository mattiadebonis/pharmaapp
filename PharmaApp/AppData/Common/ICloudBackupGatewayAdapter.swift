import Foundation
import Combine

@MainActor
final class ICloudBackupGatewayAdapter: BackupGateway {
    private let coordinator: BackupCoordinator

    init(coordinator: BackupCoordinator) {
        self.coordinator = coordinator
    }

    var state: BackupGatewayState {
        BackupGatewayState(
            status: coordinator.status,
            cloudAvailability: coordinator.cloudAvailability,
            snapshots: coordinator.snapshots,
            lastSuccessfulBackupAt: coordinator.lastSuccessfulBackupAt,
            lastErrorMessage: coordinator.lastErrorMessage,
            backupEnabled: coordinator.backupEnabled,
            restoreRevision: coordinator.restoreRevision
        )
    }

    var status: BackupStatus { coordinator.status }
    var cloudAvailability: BackupCloudAvailability { coordinator.cloudAvailability }
    var snapshots: [BackupSnapshotDescriptor] { coordinator.snapshots }
    var lastSuccessfulBackupAt: Date? { coordinator.lastSuccessfulBackupAt }
    var lastErrorMessage: String? { coordinator.lastErrorMessage }

    var backupEnabled: Bool {
        get { coordinator.backupEnabled }
        set { coordinator.backupEnabled = newValue }
    }

    func start() {
        coordinator.start()
    }

    func setEnabled(_ isEnabled: Bool) {
        coordinator.backupEnabled = isEnabled
    }

    func setAuthenticatedUserID(_ userID: String?) {
        coordinator.setAuthenticatedUserID(userID)
    }

    func refreshSnapshots() {
        coordinator.refreshSnapshots()
    }

    func observeState() -> AsyncStream<BackupGatewayState> {
        AsyncStream { continuation in
            continuation.yield(state)

            let cancellable = coordinator.objectWillChange.sink { [weak self] _ in
                guard let self else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    continuation.yield(self.state)
                }
            }

            continuation.onTermination = { _ in
                cancellable.cancel()
            }
        }
    }

    @discardableResult
    func performManualBackup() async -> Bool {
        await coordinator.performManualBackup()
    }

    @discardableResult
    func performAutomaticBackupIfNeeded() async -> Bool {
        await coordinator.performAutomaticBackupIfNeeded()
    }

    @discardableResult
    func restore(snapshotId: BackupSnapshotDescriptor.ID) async -> Bool {
        guard let snapshot = coordinator.snapshots.first(where: { $0.id == snapshotId }) else {
            return false
        }
        return await coordinator.restore(snapshot)
    }

    func listSnapshots() -> [BackupSnapshotDescriptor] {
        coordinator.snapshots
    }
}
