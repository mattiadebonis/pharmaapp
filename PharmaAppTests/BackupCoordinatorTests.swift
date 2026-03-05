import XCTest
import CoreData
@testable import PharmaApp

final class BackupCoordinatorTests: XCTestCase {
    func testBackupManifestRoundTripPreservesFields() throws {
        let manifest = BackupManifest(
            version: BackupManifest.currentVersion,
            createdAt: Date(timeIntervalSince1970: 1_730_000_000),
            appVersion: "1.2.3 (45)",
            modelName: "PharmaApp",
            authenticatedUserId: "user-123",
            deviceId: "device-abc",
            entityCounts: ["Person": 2, "Medicine": 4],
            storeFiles: ["PharmaApp.shared.sqlite", "PharmaApp.shared.sqlite-wal"],
            estimatedSizeBytes: 8_192
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BackupManifest.self, from: data)

        XCTAssertEqual(decoded, manifest)
    }

    func testBackupSettingsStoreDefaultsAndSuccessState() throws {
        let suiteName = "BackupSettingsStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var store = BackupSettingsStore(userDefaults: defaults)
        XCTAssertTrue(store.backupEnabled)
        XCTAssertNil(store.lastSuccessfulBackupAt)
        XCTAssertNil(store.lastAttemptAt)
        XCTAssertNil(store.lastErrorMessage)
        XCTAssertFalse(store.pendingChanges)

        store.pendingChanges = true
        store.lastErrorMessage = "Errore precedente"
        let successDate = Date(timeIntervalSince1970: 1_735_000_000)
        store.markBackupSucceeded(at: successDate)

        let persisted = BackupSettingsStore(userDefaults: defaults)
        XCTAssertTrue(persisted.backupEnabled)
        XCTAssertEqual(persisted.lastSuccessfulBackupAt, successDate)
        XCTAssertEqual(persisted.lastAttemptAt, successDate)
        XCTAssertNil(persisted.lastErrorMessage)
        XCTAssertFalse(persisted.pendingChanges)
    }

    func testShouldPerformAutomaticBackupRequiresEnabledAvailablePendingAndElapsedInterval() {
        let now = Date(timeIntervalSince1970: 1_736_000_000)

        XCTAssertFalse(
            BackupCoordinator.shouldPerformAutomaticBackup(
                isEnabled: false,
                availability: .available,
                hasPendingChanges: true,
                lastSuccessfulBackupAt: nil,
                now: now
            )
        )

        XCTAssertFalse(
            BackupCoordinator.shouldPerformAutomaticBackup(
                isEnabled: true,
                availability: .notAuthenticated,
                hasPendingChanges: true,
                lastSuccessfulBackupAt: nil,
                now: now
            )
        )

        XCTAssertFalse(
            BackupCoordinator.shouldPerformAutomaticBackup(
                isEnabled: true,
                availability: .available,
                hasPendingChanges: false,
                lastSuccessfulBackupAt: nil,
                now: now
            )
        )

        XCTAssertFalse(
            BackupCoordinator.shouldPerformAutomaticBackup(
                isEnabled: true,
                availability: .available,
                hasPendingChanges: true,
                lastSuccessfulBackupAt: now.addingTimeInterval(-(11 * 60 * 60)),
                now: now
            )
        )

        XCTAssertTrue(
            BackupCoordinator.shouldPerformAutomaticBackup(
                isEnabled: true,
                availability: .available,
                hasPendingChanges: true,
                lastSuccessfulBackupAt: nil,
                now: now
            )
        )

        XCTAssertTrue(
            BackupCoordinator.shouldPerformAutomaticBackup(
                isEnabled: true,
                availability: .available,
                hasPendingChanges: true,
                lastSuccessfulBackupAt: now.addingTimeInterval(-(12 * 60 * 60)),
                now: now
            )
        )
    }

    func testSnapshotsToDeleteKeepsOnlyNewestSeven() {
        let snapshots = (0..<8).map { index in
            makeSnapshotDescriptor(
                suffix: "\(index)",
                createdAt: Date(timeIntervalSince1970: TimeInterval(1_736_000_000 + index)),
                authenticatedUserId: "user-1"
            )
        }

        let snapshotsToDelete = BackupCoordinator.snapshotsToDelete(snapshots)

        XCTAssertEqual(snapshotsToDelete.count, 1)
        XCTAssertEqual(snapshotsToDelete.first?.displayName, "backup-0")
    }

    @MainActor
    func testRestoreFailsWhenSnapshotBelongsToDifferentAuthenticatedUser() async throws {
        let suiteName = "BackupCoordinatorMismatch.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let coordinator = PersistenceController(inMemory: true)
        let backupCoordinator = BackupCoordinator(
            persistenceController: coordinator,
            documentLocator: BackupDocumentLocator(fileManager: .default),
            settingsStore: BackupSettingsStore(userDefaults: defaults),
            notificationCenter: NotificationCenter()
        )
        backupCoordinator.setAuthenticatedUserID("user-1")

        let snapshot = makeSnapshotDescriptor(
            suffix: UUID().uuidString,
            createdAt: Date(),
            authenticatedUserId: "user-2"
        )

        let restored = await backupCoordinator.restore(snapshot)

        XCTAssertFalse(restored)
        XCTAssertEqual(
            backupCoordinator.lastErrorMessage,
            "Se l'utente PharmaApp non coincide con il backup selezionato, il restore non e consentito."
        )
    }

    @MainActor
    func testRestoreReplacesStoreWithSnapshotContents() async throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent(
            "BackupCoordinatorTests.\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: rootURL) }

        let storeURL = rootURL.appendingPathComponent("PharmaApp.shared.sqlite")
        let controller = PersistenceController(inMemory: false, storeURL: storeURL)
        try seedSnapshotData(in: controller.container.viewContext)
        try controller.saveViewContextIfNeeded()

        let snapshotURL = rootURL.appendingPathComponent("backup-restore.pharmabackup", isDirectory: true)
        let copiedFiles = try controller.copyStorePackage(to: snapshotURL)
        let manifest = BackupManifest(
            version: BackupManifest.currentVersion,
            createdAt: Date(timeIntervalSince1970: 1_736_100_000),
            appVersion: "Test",
            modelName: controller.modelName,
            authenticatedUserId: "user-1",
            deviceId: "device-test",
            entityCounts: try controller.entityCounts(),
            storeFiles: copiedFiles,
            estimatedSizeBytes: packageSize(at: snapshotURL)
        )
        try writeManifest(manifest, to: snapshotURL)

        try mutateStoreAfterBackup(in: controller.container.viewContext)
        try controller.saveViewContextIfNeeded()

        let suiteName = "BackupCoordinatorRestore.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let backupCoordinator = BackupCoordinator(
            persistenceController: controller,
            documentLocator: BackupDocumentLocator(fileManager: fileManager),
            settingsStore: BackupSettingsStore(userDefaults: defaults),
            notificationCenter: NotificationCenter(),
            fileManager: fileManager
        )
        backupCoordinator.setAuthenticatedUserID("user-1")

        let snapshot = BackupSnapshotDescriptor(
            url: snapshotURL,
            createdAt: manifest.createdAt,
            sizeBytes: manifest.estimatedSizeBytes,
            manifest: manifest
        )

        let restored = await backupCoordinator.restore(snapshot)

        XCTAssertTrue(restored)
        XCTAssertEqual(backupCoordinator.restoreRevision, 1)
        XCTAssertNil(backupCoordinator.lastErrorMessage)

        let context = controller.container.viewContext
        let people = try context.fetch(Person.extractPersons(includeAccount: true))
        XCTAssertEqual(people.count, 1)
        XCTAssertEqual(people.first?.nome, "Mario")
        XCTAssertTrue(people.first?.is_account == true)

        let medicines = try context.fetch(Medicine.extractMedicines())
        XCTAssertEqual(medicines.count, 1)
        XCTAssertEqual(medicines.first?.nome, "Aspirina")
    }

    private func makeSnapshotDescriptor(
        suffix: String,
        createdAt: Date,
        authenticatedUserId: String
    ) -> BackupSnapshotDescriptor {
        let manifest = BackupManifest(
            version: BackupManifest.currentVersion,
            createdAt: createdAt,
            appVersion: "Test",
            modelName: "PharmaApp",
            authenticatedUserId: authenticatedUserId,
            deviceId: "device-test",
            entityCounts: [:],
            storeFiles: ["PharmaApp.shared.sqlite"],
            estimatedSizeBytes: 0
        )

        return BackupSnapshotDescriptor(
            url: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("backup-\(suffix).pharmabackup"),
            createdAt: createdAt,
            sizeBytes: 0,
            manifest: manifest
        )
    }

    private func seedSnapshotData(in context: NSManagedObjectContext) throws {
        let account = Person(context: context)
        account.id = UUID()
        account.nome = "Mario"
        account.cognome = "Rossi"
        account.is_account = true

        let medicine = try TestCoreDataFactory.makeMedicine(context: context)
        medicine.nome = "Aspirina"
        medicine.principio_attivo = "Acido acetilsalicilico"
    }

    private func mutateStoreAfterBackup(in context: NSManagedObjectContext) throws {
        let account = try XCTUnwrap(context.fetch(Person.fetchAccountPerson()).first)
        account.nome = "Luigi"

        let extraPerson = Person(context: context)
        extraPerson.id = UUID()
        extraPerson.nome = "Extra"
        extraPerson.cognome = "Persona"
        extraPerson.is_account = false

        let medicine = try XCTUnwrap(context.fetch(Medicine.extractMedicines()).first)
        medicine.nome = "Mutata"
    }

    private func writeManifest(_ manifest: BackupManifest, to packageURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: packageURL.appendingPathComponent(BackupDocumentLocator.manifestFileName))
    }

    private func packageSize(at packageURL: URL) -> Int64 {
        let enumerator = FileManager.default.enumerator(
            at: packageURL,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var total: Int64 = 0
        while let fileURL = enumerator?.nextObject() as? URL {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }
}
