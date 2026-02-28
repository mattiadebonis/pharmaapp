import Foundation
import CoreData
#if canImport(ActivityKit)
import ActivityKit
#endif

@MainActor
protocol CriticalDoseLiveActivityRefreshing {
    func refresh(reason: String, now: Date?) async -> Date?
    func showConfirmationThenRefresh(medicineName: String) async
}

@MainActor
final class CriticalDoseLiveActivityCoordinator: CriticalDoseLiveActivityRefreshing {
    static let shared = CriticalDoseLiveActivityCoordinator(
        context: PersistenceController.shared.container.viewContext
    )

    private let planner: CriticalDoseLiveActivityPlanning?
    private let client: CriticalDoseLiveActivityClientProtocol
    private let clock: Clock
    private let container: NSPersistentContainer

    init(
        context: NSManagedObjectContext,
        planner: CriticalDoseLiveActivityPlanning? = nil,
        client: CriticalDoseLiveActivityClientProtocol = CriticalDoseLiveActivityClient(),
        clock: Clock = SystemClock(),
        container: NSPersistentContainer = PersistenceController.shared.container
    ) {
        self.planner = planner
        self.client = client
        self.clock = clock
        self.container = container
    }

    func refresh(reason: String, now: Date? = nil) async -> Date? {
        let _ = reason
        let now = now ?? clock.now()

        guard liveActivitiesEnabled else {
            await endAllActivities()
            return nil
        }

        let plan = await makePlan(now: now)
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

    func showConfirmationThenRefresh(medicineName: String) async {
        guard liveActivitiesEnabled else { return }

        let activityIDs = client.currentActivityIDs()
        guard let firstID = activityIDs.first else { return }

        // Build a confirmation state reusing the current activity's data
        let confirmationState = CriticalDoseLiveActivityAttributes.ContentState(
            primaryTherapyId: "",
            primaryMedicineId: "",
            primaryMedicineName: medicineName,
            primaryDoseText: "",
            primaryScheduledAt: Date(),
            additionalCount: 0,
            subtitleDisplay: "",
            expiryAt: Date().addingTimeInterval(10),
            confirmedTakenName: medicineName
        )

        await client.update(activityID: firstID, contentState: confirmationState, staleDate: nil)

        // Show confirmation for 3 seconds, then refresh normally
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        _ = await refresh(reason: "post-confirmation", now: nil)
    }

    private func endAllActivities() async {
        let ids = client.currentActivityIDs()
        for id in ids {
            await client.end(activityID: id, dismissalPolicy: .immediate)
        }
    }

    private func makePlan(now: Date) async -> CriticalDosePlan {
        if let planner {
            return planner.makePlan(now: now)
        }

        let backgroundContext = container.newBackgroundContext()
        backgroundContext.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy

        return await withCheckedContinuation { continuation in
            backgroundContext.perform {
                let planner = CriticalDoseLiveActivityPlanner(context: backgroundContext)
                continuation.resume(returning: planner.makePlan(now: now))
            }
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
