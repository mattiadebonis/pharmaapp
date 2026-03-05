import Foundation

struct BackupSettingsStore {
    private enum Key {
        static let enabled = "pharmaapp.backup.enabled"
        static let lastSuccessfulBackupAt = "pharmaapp.backup.lastSuccessfulBackupAt"
        static let lastAttemptAt = "pharmaapp.backup.lastAttemptAt"
        static let lastErrorMessage = "pharmaapp.backup.lastErrorMessage"
        static let pendingChanges = "pharmaapp.backup.pendingChanges"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var backupEnabled: Bool {
        get {
            if userDefaults.object(forKey: Key.enabled) == nil {
                return true
            }
            return userDefaults.bool(forKey: Key.enabled)
        }
        set {
            userDefaults.set(newValue, forKey: Key.enabled)
        }
    }

    var lastSuccessfulBackupAt: Date? {
        get { userDefaults.object(forKey: Key.lastSuccessfulBackupAt) as? Date }
        set { userDefaults.set(newValue, forKey: Key.lastSuccessfulBackupAt) }
    }

    var lastAttemptAt: Date? {
        get { userDefaults.object(forKey: Key.lastAttemptAt) as? Date }
        set { userDefaults.set(newValue, forKey: Key.lastAttemptAt) }
    }

    var lastErrorMessage: String? {
        get { userDefaults.string(forKey: Key.lastErrorMessage) }
        set { userDefaults.set(newValue, forKey: Key.lastErrorMessage) }
    }

    var pendingChanges: Bool {
        get { userDefaults.bool(forKey: Key.pendingChanges) }
        set { userDefaults.set(newValue, forKey: Key.pendingChanges) }
    }

    mutating func markBackupSucceeded(at date: Date) {
        lastSuccessfulBackupAt = date
        lastAttemptAt = date
        lastErrorMessage = nil
        pendingChanges = false
    }

    mutating func markBackupFailed(message: String, at date: Date) {
        lastAttemptAt = date
        lastErrorMessage = message
    }
}
