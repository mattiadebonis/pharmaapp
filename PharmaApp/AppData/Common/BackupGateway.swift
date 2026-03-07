import Foundation

struct BackupGatewayState: Equatable {
    let status: BackupStatus
    let cloudAvailability: BackupCloudAvailability
    let snapshots: [BackupSnapshotDescriptor]
    let lastSuccessfulBackupAt: Date?
    let lastErrorMessage: String?
    let backupEnabled: Bool
    let restoreRevision: Int
}

@MainActor
protocol BackupGateway {
    var state: BackupGatewayState { get }
    var status: BackupStatus { get }
    var cloudAvailability: BackupCloudAvailability { get }
    var snapshots: [BackupSnapshotDescriptor] { get }
    var lastSuccessfulBackupAt: Date? { get }
    var lastErrorMessage: String? { get }
    var backupEnabled: Bool { get set }

    func start()
    func setEnabled(_ isEnabled: Bool)
    func setAuthenticatedUserID(_ userID: String?)
    func refreshSnapshots()
    func observeState() -> AsyncStream<BackupGatewayState>

    @discardableResult
    func performManualBackup() async -> Bool

    @discardableResult
    func performAutomaticBackupIfNeeded() async -> Bool

    @discardableResult
    func restore(snapshotId: BackupSnapshotDescriptor.ID) async -> Bool

    func listSnapshots() -> [BackupSnapshotDescriptor]
}
