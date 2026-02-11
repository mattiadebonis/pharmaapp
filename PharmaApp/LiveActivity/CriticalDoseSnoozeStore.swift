import Foundation

protocol CriticalDoseSnoozeStoreProtocol {
    func isSnoozed(therapyId: UUID, scheduledAt: Date, now: Date) -> Bool
    @discardableResult
    func snooze(therapyId: UUID, scheduledAt: Date, now: Date, duration: TimeInterval) -> Date
    func clear(therapyId: UUID, scheduledAt: Date)
    func nextExpiry(after now: Date) -> Date?
}

final class CriticalDoseSnoozeStore: CriticalDoseSnoozeStoreProtocol {
    private let defaults: UserDefaults
    private let storageKey: String
    private let calendar: Calendar

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "critical-dose.live-activity.snooze.v1",
        calendar: Calendar = .current
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.calendar = calendar
    }

    func isSnoozed(therapyId: UUID, scheduledAt: Date, now: Date = Date()) -> Bool {
        var snapshot = loadSnapshot()
        let key = makeKey(therapyId: therapyId, scheduledAt: scheduledAt)
        guard let expiry = snapshot[key] else { return false }
        if expiry <= now {
            snapshot.removeValue(forKey: key)
            persist(snapshot)
            return false
        }
        return true
    }

    @discardableResult
    func snooze(
        therapyId: UUID,
        scheduledAt: Date,
        now: Date = Date(),
        duration: TimeInterval
    ) -> Date {
        var snapshot = loadSnapshot()
        cleanup(snapshot: &snapshot, now: now)
        let key = makeKey(therapyId: therapyId, scheduledAt: scheduledAt)
        let expiry = now.addingTimeInterval(max(1, duration))
        snapshot[key] = expiry
        persist(snapshot)
        return expiry
    }

    func clear(therapyId: UUID, scheduledAt: Date) {
        var snapshot = loadSnapshot()
        snapshot.removeValue(forKey: makeKey(therapyId: therapyId, scheduledAt: scheduledAt))
        persist(snapshot)
    }

    func nextExpiry(after now: Date = Date()) -> Date? {
        var snapshot = loadSnapshot()
        cleanup(snapshot: &snapshot, now: now)
        return snapshot.values.filter { $0 > now }.sorted().first
    }

    private func makeKey(therapyId: UUID, scheduledAt: Date) -> String {
        let bucket = Int(scheduledAt.timeIntervalSince1970 / 60)
        return "\(therapyId.uuidString)|\(bucket)"
    }

    private func loadSnapshot() -> [String: Date] {
        guard let raw = defaults.dictionary(forKey: storageKey) else { return [:] }
        var output: [String: Date] = [:]
        for (key, value) in raw {
            if let timestamp = value as? TimeInterval {
                output[key] = Date(timeIntervalSince1970: timestamp)
                continue
            }
            if let number = value as? NSNumber {
                output[key] = Date(timeIntervalSince1970: number.doubleValue)
            }
        }
        return output
    }

    private func persist(_ snapshot: [String: Date]) {
        let payload = snapshot.mapValues { $0.timeIntervalSince1970 }
        defaults.set(payload, forKey: storageKey)
    }

    private func cleanup(snapshot: inout [String: Date], now: Date) {
        let beforeCount = snapshot.count
        snapshot = snapshot.filter { $0.value > now }
        if snapshot.count != beforeCount {
            persist(snapshot)
        }
    }
}
