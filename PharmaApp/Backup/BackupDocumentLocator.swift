import Foundation

enum BackupDocumentLocatorError: LocalizedError {
    case iCloudUnavailable
    case manifestMissing
    case invalidManifest
    case snapshotNotDownloaded

    var errorDescription: String? {
        switch self {
        case .iCloudUnavailable:
            return "iCloud Drive non e disponibile su questo dispositivo."
        case .manifestMissing:
            return "Il backup selezionato non contiene un manifest valido."
        case .invalidManifest:
            return "Il manifest del backup non puo essere letto."
        case .snapshotNotDownloaded:
            return "Il backup non e stato scaricato da iCloud in tempo utile."
        }
    }
}

final class BackupDocumentLocator {
    static let containerIdentifier = "iCloud.pharmapp-1987"
    static let backupExtension = "pharmabackup"
    static let manifestFileName = "manifest.json"

    private let fileManager: FileManager
    private let decoder: JSONDecoder

    init(
        fileManager: FileManager = .default,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.fileManager = fileManager
        self.decoder = decoder
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func cloudAvailability() -> BackupCloudAvailability {
        guard fileManager.ubiquityIdentityToken != nil else {
            return .notAuthenticated
        }
        guard fileManager.url(forUbiquityContainerIdentifier: Self.containerIdentifier) != nil else {
            return .unavailable
        }
        return .available
    }

    func ubiquitousContainerURL() -> URL? {
        fileManager.url(forUbiquityContainerIdentifier: Self.containerIdentifier)
    }

    func backupDirectoryURL(createIfNeeded: Bool) throws -> URL {
        guard let containerURL = ubiquitousContainerURL() else {
            throw BackupDocumentLocatorError.iCloudUnavailable
        }
        let backupDirectoryURL = containerURL
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Backups", isDirectory: true)
        if createIfNeeded {
            try fileManager.createDirectory(
                at: backupDirectoryURL,
                withIntermediateDirectories: true
            )
        }
        return backupDirectoryURL
    }

    func makeSnapshotQuery() -> NSMetadataQuery {
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(
            format: "%K LIKE %@",
            NSMetadataItemFSNameKey,
            "*.\(Self.backupExtension)"
        )
        return query
    }

    func snapshotDescriptors(from query: NSMetadataQuery) -> [BackupSnapshotDescriptor] {
        let urls = query.results.compactMap { item -> URL? in
            guard let metadataItem = item as? NSMetadataItem else { return nil }
            return metadataItem.value(forAttribute: NSMetadataItemURLKey) as? URL
        }
        return snapshotDescriptors(for: urls)
    }

    func snapshotDescriptorsFromDisk() -> [BackupSnapshotDescriptor] {
        guard let backupDirectoryURL = try? backupDirectoryURL(createIfNeeded: true),
              let contents = try? fileManager.contentsOfDirectory(
                at: backupDirectoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }
        return snapshotDescriptors(for: contents)
    }

    func loadManifest(from packageURL: URL) throws -> BackupManifest {
        let manifestURL = packageURL.appendingPathComponent(Self.manifestFileName)
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw BackupDocumentLocatorError.manifestMissing
        }
        do {
            let data = try Data(contentsOf: manifestURL)
            return try decoder.decode(BackupManifest.self, from: data)
        } catch {
            throw BackupDocumentLocatorError.invalidManifest
        }
    }

    func packageSize(at packageURL: URL) -> Int64 {
        let enumerator = fileManager.enumerator(
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

    func ensureSnapshotDownloaded(at packageURL: URL, timeout: TimeInterval = 20) throws {
        let startDate = Date()
        if fileManager.isUbiquitousItem(at: packageURL) {
            try? fileManager.startDownloadingUbiquitousItem(at: packageURL)
        }

        while Date().timeIntervalSince(startDate) < timeout {
            let values = try? packageURL.resourceValues(forKeys: [
                .isUbiquitousItemKey,
                .ubiquitousItemDownloadingStatusKey
            ])
            if values?.isUbiquitousItem != true {
                return
            }
            if values?.ubiquitousItemDownloadingStatus == URLUbiquitousItemDownloadingStatus.current {
                return
            }
            Thread.sleep(forTimeInterval: 0.25)
        }

        throw BackupDocumentLocatorError.snapshotNotDownloaded
    }

    private func snapshotDescriptors(for urls: [URL]) -> [BackupSnapshotDescriptor] {
        urls
            .filter { $0.pathExtension == Self.backupExtension }
            .compactMap { url -> BackupSnapshotDescriptor? in
                guard let manifest = try? loadManifest(from: url) else { return nil }
                return BackupSnapshotDescriptor(
                    url: url,
                    createdAt: manifest.createdAt,
                    sizeBytes: packageSize(at: url),
                    manifest: manifest
                )
            }
            .sorted { $0.createdAt > $1.createdAt }
    }
}
