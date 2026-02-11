import Foundation
import CoreData
import Testing
@testable import PharmaApp

private final class PlannerSequenceFake: CriticalDoseLiveActivityPlanning {
    var nextPlan: CriticalDosePlan = .empty

    func makePlan(now: Date?) -> CriticalDosePlan {
        nextPlan
    }
}

private final class LiveActivityClientFake: CriticalDoseLiveActivityClientProtocol {
    var ids: [String] = []
    var requestCount = 0
    var updateCount = 0
    var endCount = 0

    func currentActivityIDs() -> [String] {
        ids
    }

    func request(
        attributes: CriticalDoseLiveActivityAttributes,
        contentState: CriticalDoseLiveActivityAttributes.ContentState,
        staleDate: Date?
    ) async throws -> String {
        requestCount += 1
        let id = "fake-\(requestCount)"
        ids = [id]
        return id
    }

    func update(
        activityID: String,
        contentState: CriticalDoseLiveActivityAttributes.ContentState,
        staleDate: Date?
    ) async {
        updateCount += 1
    }

    func end(activityID: String, dismissalPolicy: CriticalDoseActivityDismissalPolicy) async {
        endCount += 1
        ids.removeAll { $0 == activityID }
    }
}

private struct FrozenClock: Clock {
    let date: Date
    func now() -> Date { date }
}

@MainActor
struct CriticalDoseLiveActivityCoordinatorTests {
    @Test func refreshStartsActivityWhenPlanHasAggregate() async throws {
        let context = try TestCoreDataFactory.makeContainer().viewContext
        let planner = PlannerSequenceFake()
        let client = LiveActivityClientFake()
        let now = Date(timeIntervalSince1970: 1_739_000_000)

        planner.nextPlan = CriticalDosePlan(
            aggregate: makeAggregate(now: now),
            nextRefreshAt: now.addingTimeInterval(120)
        )

        let coordinator = CriticalDoseLiveActivityCoordinator(
            context: context,
            planner: planner,
            client: client,
            clock: FrozenClock(date: now)
        )

        _ = await coordinator.refresh(reason: "test", now: now)

        #expect(client.requestCount == 1)
        #expect(client.updateCount == 0)
    }

    @Test func refreshUpdatesExistingActivity() async throws {
        let context = try TestCoreDataFactory.makeContainer().viewContext
        let planner = PlannerSequenceFake()
        let client = LiveActivityClientFake()
        let now = Date(timeIntervalSince1970: 1_739_000_000)
        client.ids = ["existing"]

        planner.nextPlan = CriticalDosePlan(
            aggregate: makeAggregate(now: now),
            nextRefreshAt: nil
        )

        let coordinator = CriticalDoseLiveActivityCoordinator(
            context: context,
            planner: planner,
            client: client,
            clock: FrozenClock(date: now)
        )

        _ = await coordinator.refresh(reason: "test", now: now)

        #expect(client.requestCount == 0)
        #expect(client.updateCount == 1)
    }

    @Test func refreshEndsActivityWhenPlanIsEmpty() async throws {
        let context = try TestCoreDataFactory.makeContainer().viewContext
        let planner = PlannerSequenceFake()
        let client = LiveActivityClientFake()
        client.ids = ["existing"]

        let coordinator = CriticalDoseLiveActivityCoordinator(
            context: context,
            planner: planner,
            client: client,
            clock: FrozenClock(date: Date(timeIntervalSince1970: 1_739_000_000))
        )

        _ = await coordinator.refresh(reason: "test", now: Date(timeIntervalSince1970: 1_739_000_000))

        #expect(client.endCount == 1)
    }

    private func makeAggregate(now: Date) -> CriticalDoseAggregate {
        let primary = CriticalDoseCandidate(
            therapyId: UUID(),
            medicineId: UUID(),
            medicineName: "Othargan 5",
            doseText: "1 compressa",
            scheduledAt: now.addingTimeInterval(600)
        )
        return CriticalDoseAggregate(
            primary: primary,
            additionalCount: 1,
            subtitleDisplay: "Othargan 5 · 1 compressa +1",
            expiryAt: now.addingTimeInterval(2400)
        )
    }
}
