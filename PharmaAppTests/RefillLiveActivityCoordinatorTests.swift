import Foundation
import CoreData
import Testing
@testable import PharmaApp

@MainActor
private final class RefillGeofenceManagerFake: RefillGeofenceManaging {
    var onCandidateEntered: ((RefillPharmacyCandidate) -> Void)?
    var onCandidatesUpdated: (() -> Void)?
    var candidateById: [String: RefillPharmacyCandidate] = [:]
    var nearest: RefillPharmacyCandidate?
    var hasPendingPurchases = false

    func start() {}

    func refreshMonitoring(hasPendingPurchases: Bool) {
        self.hasPendingPurchases = hasPendingPurchases
    }

    func candidate(for pharmacyId: String) -> RefillPharmacyCandidate? {
        candidateById[pharmacyId]
    }

    func nearestCandidate() -> RefillPharmacyCandidate? {
        nearest
    }
}

private struct RefillPharmacyHoursResolverFake: RefillPharmacyHoursResolving {
    let info: RefillPharmacyOpenInfo

    func openInfo(forPharmacyName name: String, now: Date) -> RefillPharmacyOpenInfo {
        let _ = name
        let _ = now
        return info
    }
}

private final class RefillActivityStateStoreFake: RefillActivityStateStoring {
    var activeId: String?
    var pharmacyId: String?
    var startedAt: Date?

    func canShow(for pharmacyId: String, now: Date) -> Bool {
        let _ = pharmacyId
        let _ = now
        return true
    }

    func markShown(for pharmacyId: String, activityId: String, startedAt: Date, now: Date) {
        let _ = now
        self.activeId = activityId
        self.pharmacyId = pharmacyId
        self.startedAt = startedAt
    }

    func activeActivityId() -> String? { activeId }
    func activePharmacyId() -> String? { pharmacyId }
    func activeStartedAt() -> Date? { startedAt }

    func setActive(activityId: String, pharmacyId: String, startedAt: Date) {
        activeId = activityId
        self.pharmacyId = pharmacyId
        self.startedAt = startedAt
    }

    func clearActive() {
        activeId = nil
        pharmacyId = nil
        startedAt = nil
    }
}

private final class RefillLiveActivityClientFake: RefillLiveActivityClientProtocol {
    var ids: [String] = []
    var requestCount = 0
    var updateCount = 0
    var endCount = 0
    var lastRequestedAttributes: RefillActivityAttributes?
    var lastRequestedState: RefillActivityAttributes.ContentState?
    var lastUpdatedState: RefillActivityAttributes.ContentState?

    func currentActivityIDs() -> [String] {
        ids
    }

    func request(
        attributes: RefillActivityAttributes,
        contentState: RefillActivityAttributes.ContentState,
        staleDate: Date?
    ) async throws -> String {
        let _ = staleDate
        requestCount += 1
        let id = "refill-\(requestCount)"
        ids = [id]
        lastRequestedAttributes = attributes
        lastRequestedState = contentState
        return id
    }

    func update(
        activityID: String,
        contentState: RefillActivityAttributes.ContentState,
        staleDate: Date?
    ) async {
        let _ = activityID
        let _ = staleDate
        updateCount += 1
        lastUpdatedState = contentState
    }

    func end(activityID: String, dismissalPolicy: RefillActivityDismissalPolicy) async {
        let _ = dismissalPolicy
        endCount += 1
        ids.removeAll { $0 == activityID }
    }
}

private struct FrozenClock: Clock {
    let date: Date
    func now() -> Date { date }
}

@MainActor
struct RefillLiveActivityCoordinatorTests {
    @Test func refreshStartsActivityWhenStockIsUnderThreshold() async throws {
        let container = try TestCoreDataFactory.makeContainer()
        let context = container.viewContext
        try makeUnderThresholdMedicine(in: context, name: "Tachipirina", units: 2)

        let candidate = RefillPharmacyCandidate(
            id: "farm-1",
            name: "Farmacia Centrale",
            latitude: 41.9028,
            longitude: 12.4964,
            distanceMeters: 420,
            etaMinutes: 5,
            pharmacyHoursText: "oggi 09:00-19:00"
        )

        let geofence = RefillGeofenceManagerFake()
        geofence.nearest = candidate
        geofence.candidateById[candidate.id] = candidate

        let stateStore = RefillActivityStateStoreFake()
        let client = RefillLiveActivityClientFake()
        let now = Date(timeIntervalSince1970: 1_739_000_000)

        let coordinator = RefillLiveActivityCoordinator(
            context: context,
            geofenceManager: geofence,
            hoursResolver: RefillPharmacyHoursResolverFake(
                info: RefillPharmacyOpenInfo(
                    isOpen: true,
                    closingTimeText: "aperta fino alle 22:00",
                    slotText: "09:00-22:00"
                )
            ),
            stateStore: stateStore,
            client: client,
            clock: FrozenClock(date: now)
        )

        await coordinator.refresh(reason: "test", now: now)

        #expect(geofence.hasPendingPurchases)
        #expect(client.requestCount == 1)
        #expect(client.updateCount == 0)
        #expect(client.lastRequestedAttributes?.pharmacyName == "Farmacia Centrale")
        #expect(client.lastRequestedState?.purchaseNames == ["Tachipirina"])
        #expect(client.lastRequestedState?.pharmacyName == "Farmacia Centrale")
        #expect(client.lastRequestedState?.pharmacyHoursText == "aperta fino alle 22:00")
        #expect(stateStore.activeActivityId() == "refill-1")
    }

    @Test func refreshUpdatesExistingActivityForSamePharmacy() async throws {
        let container = try TestCoreDataFactory.makeContainer()
        let context = container.viewContext
        try makeUnderThresholdMedicine(in: context, name: "Moment", units: 1)

        let candidate = RefillPharmacyCandidate(
            id: "farm-2",
            name: "Farmacia Quartiere",
            latitude: 45.4642,
            longitude: 9.19,
            distanceMeters: 800,
            etaMinutes: 9,
            pharmacyHoursText: "orari non disponibili"
        )

        let geofence = RefillGeofenceManagerFake()
        geofence.nearest = candidate
        geofence.candidateById[candidate.id] = candidate

        let stateStore = RefillActivityStateStoreFake()
        let now = Date(timeIntervalSince1970: 1_739_100_000)
        stateStore.setActive(activityId: "active-1", pharmacyId: candidate.id, startedAt: now)

        let client = RefillLiveActivityClientFake()
        client.ids = ["active-1"]

        let coordinator = RefillLiveActivityCoordinator(
            context: context,
            geofenceManager: geofence,
            hoursResolver: RefillPharmacyHoursResolverFake(
                info: RefillPharmacyOpenInfo(
                    isOpen: false,
                    closingTimeText: nil,
                    slotText: nil
                )
            ),
            stateStore: stateStore,
            client: client,
            clock: FrozenClock(date: now)
        )

        await coordinator.refresh(reason: "test-update", now: now)

        #expect(client.requestCount == 0)
        #expect(client.updateCount == 1)
        #expect(client.lastUpdatedState?.purchaseNames == ["Moment"])
    }

    @discardableResult
    private func makeUnderThresholdMedicine(
        in context: NSManagedObjectContext,
        name: String,
        units: Int
    ) throws -> Medicine {
        let medicine = try TestCoreDataFactory.makeMedicine(context: context)
        medicine.nome = name
        let package = try TestCoreDataFactory.makePackage(context: context, medicine: medicine)
        let stockService = StockService(context: context)
        stockService.setUnits(units, for: package)
        try context.save()
        return medicine
    }
}
