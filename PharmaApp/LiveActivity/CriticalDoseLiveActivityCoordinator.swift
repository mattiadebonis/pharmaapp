import Foundation
import CoreData
#if canImport(ActivityKit)
import ActivityKit
#endif

@MainActor
protocol CriticalDoseLiveActivityRefreshing {
    func refresh(reason: String, now: Date?) async -> Date?
}

@MainActor
final class CriticalDoseLiveActivityCoordinator: CriticalDoseLiveActivityRefreshing {
    static let shared = CriticalDoseLiveActivityCoordinator(
        context: PersistenceController.shared.container.viewContext
    )

    private let planner: CriticalDoseLiveActivityPlanning
    private let client: CriticalDoseLiveActivityClientProtocol
    private let clock: Clock

    init(
        context: NSManagedObjectContext,
        planner: CriticalDoseLiveActivityPlanning? = nil,
        client: CriticalDoseLiveActivityClientProtocol = CriticalDoseLiveActivityClient(),
        clock: Clock = SystemClock()
    ) {
        self.planner = planner ?? CriticalDoseLiveActivityPlanner(context: context)
        self.client = client
        self.clock = clock
    }

    func refresh(reason: String, now: Date? = nil) async -> Date? {
        let _ = reason
        let now = now ?? clock.now()

        guard liveActivitiesEnabled else {
            await endAllActivities()
            return nil
        }

        let plan = planner.makePlan(now: now)
        guard let aggregate = plan.aggregate else {
            await endAllActivities()
            return plan.nextRefreshAt
        }

        let attributes = CriticalDoseLiveActivityAttributes(
            title: "È quasi ora",
            microcopy: "Quando sei pronto"
        )
        let state = CriticalDoseLiveActivityAttributes.ContentState(
            primaryTherapyId: aggregate.primary.therapyId.uuidString,
            primaryMedicineId: aggregate.primary.medicineId.uuidString,
            primaryMedicineName: aggregate.primary.medicineName,
            primaryDoseText: aggregate.primary.doseText,
            primaryScheduledAt: aggregate.primary.scheduledAt,
            additionalCount: aggregate.additionalCount,
            subtitleDisplay: aggregate.subtitleDisplay,
            expiryAt: aggregate.expiryAt
        )

        var activityIDs = client.currentActivityIDs()
        if let firstID = activityIDs.first {
            await client.update(activityID: firstID, contentState: state, staleDate: aggregate.expiryAt)
            activityIDs.removeFirst()
            for id in activityIDs {
                await client.end(activityID: id, dismissalPolicy: .immediate)
            }
        } else {
            do {
                _ = try await client.request(attributes: attributes, contentState: state, staleDate: aggregate.expiryAt)
            } catch {
                // Ignore transient ActivityKit errors and retry on the next checkpoint.
            }
        }

        return plan.nextRefreshAt
    }

    private func endAllActivities() async {
        let ids = client.currentActivityIDs()
        for id in ids {
            await client.end(activityID: id, dismissalPolicy: .immediate)
        }
    }

    private var liveActivitiesEnabled: Bool {
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            return ActivityAuthorizationInfo().areActivitiesEnabled
        }
        #endif
        return false
    }
}
