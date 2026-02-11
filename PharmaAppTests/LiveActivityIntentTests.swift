import Foundation
import Testing
@testable import PharmaApp

@MainActor
private final class IntentActionPerformerFake: CriticalDoseActionPerforming {
    var markTakenCalls = 0
    var remindLaterCalls = 0

    func markTaken(contentState: CriticalDoseLiveActivityAttributes.ContentState) -> Bool {
        markTakenCalls += 1
        return true
    }

    func remindLater(contentState: CriticalDoseLiveActivityAttributes.ContentState, now: Date) async -> Bool {
        remindLaterCalls += 1
        return true
    }
}

@MainActor
private final class IntentRefresherFake: CriticalDoseLiveActivityRefreshing {
    var refreshCalls = 0

    func refresh(reason: String, now: Date?) async -> Date? {
        refreshCalls += 1
        return nil
    }
}

@MainActor
struct LiveActivityIntentTests {
    @Test func markTakenIntentCallsActionAndRefresh() async throws {
        let performer = IntentActionPerformerFake()
        let refresher = IntentRefresherFake()
        let previousPerformer = LiveActivityMarkTakenIntent.actionPerformer
        let previousRefresher = LiveActivityMarkTakenIntent.liveActivityRefresher

        LiveActivityMarkTakenIntent.actionPerformer = performer
        LiveActivityMarkTakenIntent.liveActivityRefresher = refresher
        defer {
            LiveActivityMarkTakenIntent.actionPerformer = previousPerformer
            LiveActivityMarkTakenIntent.liveActivityRefresher = previousRefresher
        }

        let intent = LiveActivityMarkTakenIntent(
            therapyId: UUID().uuidString,
            medicineId: UUID().uuidString,
            medicineName: "Othargan 5",
            doseText: "1 compressa",
            scheduledAt: Date(timeIntervalSince1970: 1_739_000_000)
        )

        _ = try await intent.perform()

        #expect(performer.markTakenCalls == 1)
        #expect(refresher.refreshCalls == 1)
    }

    @Test func remindLaterIntentCallsActionAndRefresh() async throws {
        let performer = IntentActionPerformerFake()
        let refresher = IntentRefresherFake()
        let previousPerformer = LiveActivityRemindLaterIntent.actionPerformer
        let previousRefresher = LiveActivityRemindLaterIntent.liveActivityRefresher

        LiveActivityRemindLaterIntent.actionPerformer = performer
        LiveActivityRemindLaterIntent.liveActivityRefresher = refresher
        defer {
            LiveActivityRemindLaterIntent.actionPerformer = previousPerformer
            LiveActivityRemindLaterIntent.liveActivityRefresher = previousRefresher
        }

        let intent = LiveActivityRemindLaterIntent(
            therapyId: UUID().uuidString,
            medicineId: UUID().uuidString,
            medicineName: "Othargan 5",
            doseText: "1 compressa",
            scheduledAt: Date(timeIntervalSince1970: 1_739_000_000)
        )

        _ = try await intent.perform()

        #expect(performer.remindLaterCalls == 1)
        #expect(refresher.refreshCalls == 1)
    }
}
