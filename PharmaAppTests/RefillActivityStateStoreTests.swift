import Foundation
import Testing
@testable import PharmaApp

struct RefillActivityStateStoreTests {
    @Test func cooldownsAreAppliedForGlobalAndSamePharmacy() {
        let defaults = UserDefaults(suiteName: "RefillActivityStateStoreTests.cooldowns")!
        defaults.removePersistentDomain(forName: "RefillActivityStateStoreTests.cooldowns")

        let store = UserDefaultsRefillActivityStateStore(defaults: defaults)
        let now = Date(timeIntervalSince1970: 1_739_000_000)

        #expect(store.canShow(for: "pharmacy-a", now: now))

        store.markShown(for: "pharmacy-a", activityId: "activity-1", startedAt: now, now: now)

        #expect(store.canShow(for: "pharmacy-a", now: now.addingTimeInterval(60 * 60)) == false)
        #expect(store.canShow(for: "pharmacy-b", now: now.addingTimeInterval(60 * 60)) == false)

        #expect(store.canShow(for: "pharmacy-b", now: now.addingTimeInterval(9 * 60 * 60)))
        #expect(store.canShow(for: "pharmacy-a", now: now.addingTimeInterval(9 * 60 * 60)) == false)
        #expect(store.canShow(for: "pharmacy-a", now: now.addingTimeInterval(25 * 60 * 60)))
    }

    @Test func activeStateCanBeSetAndCleared() {
        let defaults = UserDefaults(suiteName: "RefillActivityStateStoreTests.active")!
        defaults.removePersistentDomain(forName: "RefillActivityStateStoreTests.active")

        let store = UserDefaultsRefillActivityStateStore(defaults: defaults)
        let startedAt = Date(timeIntervalSince1970: 1_739_000_500)

        store.setActive(activityId: "a1", pharmacyId: "p1", startedAt: startedAt)

        #expect(store.activeActivityId() == "a1")
        #expect(store.activePharmacyId() == "p1")
        #expect(store.activeStartedAt() == startedAt)

        store.clearActive()

        #expect(store.activeActivityId() == nil)
        #expect(store.activePharmacyId() == nil)
        #expect(store.activeStartedAt() == nil)
    }
}
