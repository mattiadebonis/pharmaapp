import Foundation

enum BackupCloudAvailability: Equatable {
    case available
    case notAuthenticated
    case unavailable

    var description: String {
        switch self {
        case .available:
            return "Disponibile"
        case .notAuthenticated:
            return "iCloud non configurato sul dispositivo"
        case .unavailable:
            return "Non disponibile"
        }
    }
}

enum BackupStatus: Equatable {
    case disabled
    case unavailable
    case idle
    case running
    case failed(String)
    case restoring

    var isBusy: Bool {
        switch self {
        case .running, .restoring:
            return true
        case .disabled, .unavailable, .idle, .failed:
            return false
        }
    }

    var description: String {
        switch self {
        case .disabled:
            return "Backup automatico disattivato"
        case .unavailable:
            return "Backup iCloud non disponibile"
        case .idle:
            return "Pronto"
        case .running:
            return "Backup in corso"
        case .failed(let message):
            return message
        case .restoring:
            return "Ripristino in corso"
        }
    }
}

struct BackupManifest: Codable, Equatable {
    static let currentVersion = 1

    let version: Int
    let createdAt: Date
    let appVersion: String
    let modelName: String
    let authenticatedUserId: String
    let deviceId: String
    let entityCounts: [String: Int]
    let storeFiles: [String]
    let estimatedSizeBytes: Int64
}

struct BackupSnapshotDescriptor: Identifiable, Equatable {
    let url: URL
    let createdAt: Date
    let sizeBytes: Int64
    let manifest: BackupManifest

    var id: URL { url }
    var displayName: String { url.deletingPathExtension().lastPathComponent }
}
