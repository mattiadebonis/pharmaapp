import Foundation
import CoreData
import UIKit

final class BackupCoordinator: ObservableObject {
    private enum Constants {
        static let automaticBackupInterval: TimeInterval = 12 * 60 * 60
        static let retentionLimit = 7
    }

    @Published private(set) var status: BackupStatus
    @Published private(set) var cloudAvailability: BackupCloudAvailability
    @Published private(set) var snapshots: [BackupSnapshotDescriptor]
    @Published private(set) var lastSuccessfulBackupAt: Date?
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var restoreRevision: Int
    @Published var backupEnabled: Bool {
        didSet {
            settingsStore.backupEnabled = backupEnabled
            applyStableStatus()
        }
    }

    private let persistenceController: PersistenceController
    private let documentLocator: BackupDocumentLocator
    private let notificationCenter: NotificationCenter
    private let fileManager: FileManager
    private let dateProvider: () -> Date

    private var settingsStore: BackupSettingsStore
    private var metadataQuery: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private var didStart = false
    private var isPerformingOperation = false
    private var authenticatedUserID: String?
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid

    init(
        persistenceController: PersistenceController = .shared,
        documentLocator: BackupDocumentLocator = BackupDocumentLocator(),
        settingsStore: BackupSettingsStore = BackupSettingsStore(),
        notificationCenter: NotificationCenter = .default,
        fileManager: FileManager = .default,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.persistenceController = persistenceController
        self.documentLocator = documentLocator
        self.settingsStore = settingsStore
        self.notificationCenter = notificationCenter
        self.fileManager = fileManager
        self.dateProvider = dateProvider
        self.backupEnabled = settingsStore.backupEnabled
        self.lastSuccessfulBackupAt = settingsStore.lastSuccessfulBackupAt
        self.lastErrorMessage = settingsStore.lastErrorMessage
        self.cloudAvailability = documentLocator.cloudAvailability()
        self.snapshots = []
        self.restoreRevision = 0
        self.status = settingsStore.backupEnabled ? .idle : .disabled
        applyStableStatus()
    }

    deinit {
        observers.forEach { notificationCenter.removeObserver($0) }
        metadataQuery?.stop()
    }

    func start() {
        guard !didStart else {
            refreshCloudAvailability()
            refreshSnapshots()
            return
        }
        didStart = true

        observers.append(
            notificationCenter.addObserver(
                forName: .NSManagedObjectContextDidSave,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.handleContextDidSave(notification)
            }
        )

        observers.append(
            notificationCenter.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    _ = await self?.performAutomaticBackupIfNeeded()
                }
            }
        )

        observers.append(
            notificationCenter.addObserver(
                forName: NSNotification.Name.NSUbiquityIdentityDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.handleUbiquityIdentityDidChange()
            }
        )

        refreshCloudAvailability()
        startMetadataDiscoveryIfNeeded()
        refreshSnapshots()
    }

    func setAuthenticatedUserID(_ userID: String?) {
        authenticatedUserID = normalized(userID)
    }

    @discardableResult
    @MainActor
    func performManualBackup() async -> Bool {
        await performBackup(force: true)
    }

    @discardableResult
    @MainActor
    func performAutomaticBackupIfNeeded() async -> Bool {
        await performBackup(force: false)
    }

    @MainActor
    func restore(_ snapshot: BackupSnapshotDescriptor) async -> Bool {
        guard !isPerformingOperation else { return false }

        guard Self.canRestore(snapshot: snapshot, authenticatedUserID: authenticatedUserID) else {
            let message = "Se l'utente PharmaApp non coincide con il backup selezionato, il restore non e consentito."
            recordFailure(message)
            return false
        }

        isPerformingOperation = true
        status = .restoring
        beginBackgroundTask(name: "pharmaapp.restore")
        defer {
            isPerformingOperation = false
            endBackgroundTaskIfNeeded()
            applyStableStatus()
        }

        do {
            try documentLocator.ensureSnapshotDownloaded(at: snapshot.url)
            let stagingRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            let stagedPackageURL = stagingRoot.appendingPathComponent(snapshot.url.lastPathComponent, isDirectory: true)
            try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
            try fileManager.copyItem(at: snapshot.url, to: stagedPackageURL)
            try persistenceController.replaceStore(with: stagedPackageURL)
            try? fileManager.removeItem(at: stagingRoot)
            settingsStore.pendingChanges = false
            settingsStore.lastErrorMessage = nil
            lastErrorMessage = nil
            restoreRevision += 1
            refreshSnapshots()
            return true
        } catch {
            recordFailure(error.localizedDescription)
            return false
        }
    }

    func refreshSnapshots() {
        let resolvedSnapshots: [BackupSnapshotDescriptor]
        if let metadataQuery {
            metadataQuery.disableUpdates()
            let querySnapshots = documentLocator.snapshotDescriptors(from: metadataQuery)
            metadataQuery.enableUpdates()
            resolvedSnapshots = querySnapshots.isEmpty
                ? documentLocator.snapshotDescriptorsFromDisk()
                : querySnapshots
        } else {
            resolvedSnapshots = documentLocator.snapshotDescriptorsFromDisk()
        }
        snapshots = resolvedSnapshots
        applyStableStatus()
    }

    static func shouldPerformAutomaticBackup(
        isEnabled: Bool,
        availability: BackupCloudAvailability,
        hasPendingChanges: Bool,
        lastSuccessfulBackupAt: Date?,
        now: Date,
        minimumInterval: TimeInterval = Constants.automaticBackupInterval
    ) -> Bool {
        guard isEnabled else { return false }
        guard availability == .available else { return false }
        guard hasPendingChanges else { return false }
        guard let lastSuccessfulBackupAt else { return true }
        return now.timeIntervalSince(lastSuccessfulBackupAt) >= minimumInterval
    }

    static func snapshotsToDelete(
        _ snapshots: [BackupSnapshotDescriptor],
        retentionLimit: Int = Constants.retentionLimit
    ) -> [BackupSnapshotDescriptor] {
        guard snapshots.count > retentionLimit else { return [] }
        return Array(
            snapshots
                .sorted { $0.createdAt > $1.createdAt }
                .dropFirst(retentionLimit)
        )
    }

    static func canRestore(snapshot: BackupSnapshotDescriptor, authenticatedUserID: String?) -> Bool {
        guard let authenticatedUserID else { return false }
        return snapshot.manifest.authenticatedUserId == authenticatedUserID
    }

    private func performBackup(force: Bool) async -> Bool {
        guard !isPerformingOperation else { return false }

        refreshCloudAvailability()
        guard cloudAvailability == .available else {
            applyStableStatus()
            return false
        }

        let now = dateProvider()
        let shouldRun = force || Self.shouldPerformAutomaticBackup(
            isEnabled: backupEnabled,
            availability: cloudAvailability,
            hasPendingChanges: settingsStore.pendingChanges,
            lastSuccessfulBackupAt: settingsStore.lastSuccessfulBackupAt,
            now: now
        )
        guard shouldRun else { return false }

        guard let authenticatedUserID = normalized(authenticatedUserID) else {
            recordFailure("Accedi a PharmaApp per creare un backup.")
            return false
        }

        isPerformingOperation = true
        status = .running
        beginBackgroundTask(name: "pharmaapp.backup")
        defer {
            isPerformingOperation = false
            endBackgroundTaskIfNeeded()
            applyStableStatus()
        }

        do {
            settingsStore.lastAttemptAt = now
            let snapshot = try createSnapshot(authenticatedUserID: authenticatedUserID, now: now)
            var updatedStore = settingsStore
            updatedStore.markBackupSucceeded(at: snapshot.createdAt)
            settingsStore = updatedStore
            lastSuccessfulBackupAt = snapshot.createdAt
            lastErrorMessage = nil
            refreshSnapshots()
            return true
        } catch {
            recordFailure(error.localizedDescription, at: now)
            return false
        }
    }

    private func createSnapshot(authenticatedUserID: String, now: Date) throws -> BackupSnapshotDescriptor {
        let backupDirectoryURL = try documentLocator.backupDirectoryURL(createIfNeeded: true)
        let snapshotName = snapshotPackageName(for: now)
        let stagingRootURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let localPackageURL = stagingRootURL.appendingPathComponent(snapshotName, isDirectory: true)
        let destinationURL = backupDirectoryURL.appendingPathComponent(snapshotName, isDirectory: true)

        try fileManager.createDirectory(at: stagingRootURL, withIntermediateDirectories: true)

        do {
            let copiedFiles = try persistenceController.copyStorePackage(to: localPackageURL)
            let manifest = BackupManifest(
                version: BackupManifest.currentVersion,
                createdAt: now,
                appVersion: appVersion(),
                modelName: persistenceController.modelName,
                authenticatedUserId: authenticatedUserID,
                deviceId: UserIdentityProvider.shared.deviceId,
                entityCounts: try persistenceController.entityCounts(),
                storeFiles: copiedFiles,
                estimatedSizeBytes: documentLocator.packageSize(at: localPackageURL)
            )
            try writeManifest(manifest, to: localPackageURL)

            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }

            do {
                try fileManager.setUbiquitous(true, itemAt: localPackageURL, destinationURL: destinationURL)
            } catch {
                try fileManager.copyItem(at: localPackageURL, to: destinationURL)
            }

            try? fileManager.removeItem(at: stagingRootURL)
            trimSnapshotRetentionIfNeeded()

            return BackupSnapshotDescriptor(
                url: destinationURL,
                createdAt: manifest.createdAt,
                sizeBytes: manifest.estimatedSizeBytes,
                manifest: manifest
            )
        } catch {
            try? fileManager.removeItem(at: stagingRootURL)
            throw error
        }
    }

    private func trimSnapshotRetentionIfNeeded() {
        let currentSnapshots = documentLocator.snapshotDescriptorsFromDisk()
        for snapshot in Self.snapshotsToDelete(currentSnapshots) {
            try? fileManager.removeItem(at: snapshot.url)
        }
    }

    private func writeManifest(_ manifest: BackupManifest, to packageURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: packageURL.appendingPathComponent(BackupDocumentLocator.manifestFileName))
    }

    private func snapshotPackageName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        return "\(formatter.string(from: date)).\(BackupDocumentLocator.backupExtension)"
    }

    private func appVersion() -> String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (shortVersion, buildVersion) {
        case let (shortVersion?, buildVersion?) where !shortVersion.isEmpty && !buildVersion.isEmpty:
            return "\(shortVersion) (\(buildVersion))"
        case let (shortVersion?, _):
            return shortVersion
        case let (_, buildVersion?):
            return buildVersion
        default:
            return "Unknown"
        }
    }

    private func startMetadataDiscoveryIfNeeded() {
        guard cloudAvailability == .available else {
            metadataQuery?.stop()
            metadataQuery = nil
            return
        }
        guard metadataQuery == nil else { return }

        let query = documentLocator.makeSnapshotQuery()
        observers.append(
            notificationCenter.addObserver(
                forName: .NSMetadataQueryDidFinishGathering,
                object: query,
                queue: .main
            ) { [weak self] _ in
                self?.refreshSnapshots()
            }
        )
        observers.append(
            notificationCenter.addObserver(
                forName: .NSMetadataQueryDidUpdate,
                object: query,
                queue: .main
            ) { [weak self] _ in
                self?.refreshSnapshots()
            }
        )
        metadataQuery = query
        query.start()
    }

    private func handleContextDidSave(_ notification: Notification) {
        guard !isPerformingOperation else { return }
        guard let context = notification.object as? NSManagedObjectContext else { return }
        guard context.persistentStoreCoordinator === persistenceController.container.persistentStoreCoordinator else {
            return
        }
        let inserted = (notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject>) ?? []
        let updated = (notification.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject>) ?? []
        let deleted = (notification.userInfo?[NSDeletedObjectsKey] as? Set<NSManagedObject>) ?? []
        guard !inserted.isEmpty || !updated.isEmpty || !deleted.isEmpty else { return }
        settingsStore.pendingChanges = true
    }

    private func handleUbiquityIdentityDidChange() {
        refreshCloudAvailability()
        startMetadataDiscoveryIfNeeded()
        refreshSnapshots()
    }

    private func refreshCloudAvailability() {
        cloudAvailability = documentLocator.cloudAvailability()
        startMetadataDiscoveryIfNeeded()
        applyStableStatus()
    }

    private func applyStableStatus() {
        guard !isPerformingOperation else { return }
        if cloudAvailability != .available {
            status = .unavailable
            return
        }
        if let lastErrorMessage, !lastErrorMessage.isEmpty {
            status = .failed(lastErrorMessage)
            return
        }
        status = backupEnabled ? .idle : .disabled
    }

    private func recordFailure(_ message: String, at date: Date? = nil) {
        let now = date ?? dateProvider()
        var updatedStore = settingsStore
        updatedStore.markBackupFailed(message: message, at: now)
        settingsStore = updatedStore
        lastErrorMessage = message
        status = .failed(message)
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func beginBackgroundTask(name: String) {
        guard backgroundTaskIdentifier == .invalid else { return }
        backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            self?.endBackgroundTaskIfNeeded()
        }
    }

    private func endBackgroundTaskIfNeeded() {
        guard backgroundTaskIdentifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
        backgroundTaskIdentifier = .invalid
    }
}
