import Foundation
import CoreData

// MARK: - MigrationCoordinator

/// Orchestrates the one-time "big bang" migration from local CoreData to FastAPI backend.
///
/// **Flow on first launch of the migrated version:**
/// 1. Verify user is authenticated
/// 2. Clear all local Core Data operational entities
/// 3. Disable iCloud backup
/// 4. Call `GET /v1/bootstrap` to populate the local Core Data mirror
/// 5. Set `BackendType = .fastapi` in UserDefaults
/// 6. Set migration-completed flag
///
/// After migration, the app restarts its provider as FastAPI on next launch.
@MainActor
final class MigrationCoordinator: ObservableObject {

    // MARK: - UserDefaults Keys

    private static let migrationCompletedKey = "pharmaapp.migration.fastapi.v1"
    private static let backendKey = "pharmaapp.data_backend"

    // MARK: - Published State

    @Published private(set) var state: MigrationState = .idle
    @Published private(set) var errorMessage: String?

    enum MigrationState: Equatable {
        case idle               // Not started
        case checking           // Checking if migration is needed
        case notNeeded          // Already migrated or not applicable
        case ready              // Migration needed, ready to start
        case migrating          // Migration in progress
        case completed          // Successfully completed
        case failed             // Migration failed (retryable)
    }

    // MARK: - Dependencies

    private let userDefaults: UserDefaults
    private let persistenceController: PersistenceController

    // MARK: - Init

    init(
        userDefaults: UserDefaults = .standard,
        persistenceController: PersistenceController = .shared
    ) {
        self.userDefaults = userDefaults
        self.persistenceController = persistenceController
    }

    // MARK: - Migration Check

    /// Returns `true` if migration to FastAPI is needed.
    var isMigrationNeeded: Bool {
        !userDefaults.bool(forKey: Self.migrationCompletedKey)
    }

    /// Returns `true` if the app is already using the FastAPI backend.
    var isUsingFastAPI: Bool {
        userDefaults.string(forKey: Self.backendKey) == BackendType.fastapi.rawValue
    }

    /// Check whether migration is needed and update state accordingly.
    func checkMigrationStatus() {
        state = .checking
        if userDefaults.bool(forKey: Self.migrationCompletedKey) {
            state = .notNeeded
        } else {
            state = .ready
        }
    }

    // MARK: - Perform Migration

    /// Performs the full migration:
    /// 1. Clears local Core Data operational data
    /// 2. Disables iCloud backup
    /// 3. Bootstraps from the FastAPI server
    /// 4. Sets the backend to FastAPI
    /// 5. Marks migration as completed
    ///
    /// - Parameter client: The FastAPIClient to use for bootstrapping.
    func performMigration(client: FastAPIClient) async {
        state = .migrating
        errorMessage = nil

        do {
            // Step 1: Clear all local operational Core Data entities
            print("[Migration] Clearing local Core Data operational data...")
            clearOperationalCoreData()

            // Step 2: Disable iCloud backup
            print("[Migration] Disabling iCloud backup...")
            disableBackup()

            // Step 3: Bootstrap from server
            print("[Migration] Bootstrapping from FastAPI server...")
            let dataSync = FastAPIDataSync(
                client: client,
                persistenceController: persistenceController
            )
            try await dataSync.performBootstrapSync()

            // Step 4: Set backend to FastAPI
            print("[Migration] Setting backend to FastAPI...")
            userDefaults.set(BackendType.fastapi.rawValue, forKey: Self.backendKey)

            // Step 5: Mark migration as completed
            userDefaults.set(true, forKey: Self.migrationCompletedKey)
            userDefaults.synchronize()

            state = .completed
            print("[Migration] Migration completed successfully!")

        } catch {
            state = .failed
            errorMessage = error.localizedDescription
            print("[Migration] Migration failed: \(error)")
        }
    }

    // MARK: - Helpers

    /// Clears all operational Core Data entities (same entities as FastAPIDataSync.clearOperationalData).
    private func clearOperationalCoreData() {
        let context = persistenceController.container.viewContext
        let entityNames = [
            "MonitoringMeasurement", "DoseEventRecord", "Log", "Stock",
            "Dose", "Therapy", "MedicinePackage", "Package", "Medicine",
            "Cabinet", "Doctor", "Person"
        ]
        for entityName in entityNames {
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
            deleteRequest.resultType = .resultTypeObjectIDs
            do {
                let result = try context.execute(deleteRequest) as? NSBatchDeleteResult
                if let objectIDs = result?.result as? [NSManagedObjectID] {
                    NSManagedObjectContext.mergeChanges(
                        fromRemoteContextSave: [NSDeletedObjectsKey: objectIDs],
                        into: [context]
                    )
                }
            } catch {
                print("[Migration] Failed to clear \(entityName): \(error)")
            }
        }
    }

    /// Disables iCloud backup by setting the backup-enabled UserDefaults flag to false.
    private func disableBackup() {
        userDefaults.set(false, forKey: "pharmaapp.backup.enabled")
    }

    /// Resets migration state so the user can retry.
    func resetForRetry() {
        state = .ready
        errorMessage = nil
    }

    /// Skips migration (for debugging / development only).
    func skipMigration() {
        userDefaults.set(true, forKey: Self.migrationCompletedKey)
        state = .completed
    }
}
