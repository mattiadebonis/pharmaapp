import Foundation
import Testing
@testable import PharmaApp

struct CriticalDoseSnoozeStoreTests {
    @Test func snoozeStoresAndExpires() {
        let defaults = UserDefaults(suiteName: "CriticalDoseSnoozeStoreTests.suite")!
        defaults.removePersistentDomain(forName: "CriticalDoseSnoozeStoreTests.suite")

        let store = CriticalDoseSnoozeStore(defaults: defaults, storageKey: "test-key")
        let therapyId = UUID()
        let scheduledAt = Date(timeIntervalSince1970: 1_739_000_000)
        let now = Date(timeIntervalSince1970: 1_739_000_100)

        #expect(store.isSnoozed(therapyId: therapyId, scheduledAt: scheduledAt, now: now) == false)

        let expiry = store.snooze(
            therapyId: therapyId,
            scheduledAt: scheduledAt,
            now: now,
            duration: 600
        )
        #expect(expiry == now.addingTimeInterval(600))
        #expect(store.isSnoozed(therapyId: therapyId, scheduledAt: scheduledAt, now: now.addingTimeInterval(1)) == true)
        #expect(store.isSnoozed(therapyId: therapyId, scheduledAt: scheduledAt, now: expiry.addingTimeInterval(1)) == false)
    }

    @Test func nextExpiryReturnsNearestFutureDate() {
        let defaults = UserDefaults(suiteName: "CriticalDoseSnoozeStoreTests.next")!
        defaults.removePersistentDomain(forName: "CriticalDoseSnoozeStoreTests.next")

        let store = CriticalDoseSnoozeStore(defaults: defaults, storageKey: "test-key-next")
        let now = Date(timeIntervalSince1970: 1_739_000_000)
        let baseScheduled = Date(timeIntervalSince1970: 1_739_100_000)

        _ = store.snooze(therapyId: UUID(), scheduledAt: baseScheduled, now: now, duration: 900)
        _ = store.snooze(therapyId: UUID(), scheduledAt: baseScheduled.addingTimeInterval(60), now: now, duration: 300)

        let nearest = store.nextExpiry(after: now)
        #expect(nearest == now.addingTimeInterval(300))
    }
}
