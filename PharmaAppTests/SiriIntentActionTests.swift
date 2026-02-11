import XCTest
import CoreData
@testable import PharmaApp

final class SiriIntentActionTests: XCTestCase {
    func testSegnaAssuntoCreaLogIntake() throws {
        let (context, medicine, _) = try makeMedicineFixture(name: "Tachipirina")
        let facade = SiriIntentFacade(
            context: context,
            operationIdProvider: InMemoryOperationIdProvider(),
            routeStore: InMemoryPendingRouteStore()
        )

        let result = facade.markTaken(medicineID: medicine.id.uuidString)

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(fetchLogs(ofType: "intake", context: context).count, 1)
    }

    func testSegnaCompratoCreaLogPurchase() throws {
        let (context, medicine, _) = try makeMedicineFixture(name: "Aspirina")
        let facade = SiriIntentFacade(
            context: context,
            operationIdProvider: InMemoryOperationIdProvider(),
            routeStore: InMemoryPendingRouteStore()
        )

        let result = facade.markPurchased(medicineID: medicine.id.uuidString)

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(fetchLogs(ofType: "purchase", context: context).count, 1)
    }

    func testRicettaRicevutaCreaLogPrescriptionReceived() throws {
        let (context, medicine, _) = try makeMedicineFixture(name: "Augmentin", requiresPrescription: true)
        let facade = SiriIntentFacade(
            context: context,
            operationIdProvider: InMemoryOperationIdProvider(),
            routeStore: InMemoryPendingRouteStore()
        )

        let result = facade.markPrescriptionReceived(medicineID: medicine.id.uuidString)

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(fetchLogs(ofType: "new_prescription", context: context).count, 1)
    }

    func testDoppiaInvocazioneRavvicinataNonDuplicaLog() throws {
        let (context, medicine, _) = try makeMedicineFixture(name: "Ibuprofene")
        let provider = InMemoryOperationIdProvider()
        let facade = SiriIntentFacade(
            context: context,
            operationIdProvider: provider,
            routeStore: InMemoryPendingRouteStore()
        )

        _ = facade.markPurchased(medicineID: medicine.id.uuidString)
        _ = facade.markPurchased(medicineID: medicine.id.uuidString)

        XCTAssertEqual(fetchLogs(ofType: "purchase", context: context).count, 1)
    }

    private func makeMedicineFixture(
        name: String,
        requiresPrescription: Bool = false
    ) throws -> (NSManagedObjectContext, Medicine, Package) {
        let container = try TestCoreDataFactory.makeContainer()
        let context = container.viewContext
        let medicine = try TestCoreDataFactory.makeMedicine(context: context)
        medicine.nome = name
        medicine.obbligo_ricetta = requiresPrescription
        medicine.in_cabinet = true
        let package = try TestCoreDataFactory.makePackage(context: context, medicine: medicine, numero: 10)
        try context.save()
        return (context, medicine, package)
    }

    private func fetchLogs(ofType type: String, context: NSManagedObjectContext) -> [Log] {
        let request: NSFetchRequest<Log> = Log.fetchRequest() as! NSFetchRequest<Log>
        request.predicate = NSPredicate(format: "type == %@", type)
        return (try? context.fetch(request)) ?? []
    }
}

private final class InMemoryOperationIdProvider: OperationIdProviding {
    private var storage: [OperationKey: UUID] = [:]

    func operationId(for key: OperationKey, ttl: TimeInterval) -> UUID {
        if let existing = storage[key] {
            return existing
        }
        let id = UUID()
        storage[key] = id
        return id
    }

    func clear(_ key: OperationKey) {
        storage.removeValue(forKey: key)
    }

    func newOperationId() -> UUID {
        UUID()
    }
}

private final class InMemoryPendingRouteStore: PendingAppRouteStoring {
    private var route: AppRoute?

    func save(route: AppRoute) {
        self.route = route
    }

    func loadRoute() -> AppRoute? {
        route
    }

    func clearRoute() {
        route = nil
    }

    func consumeRoute() -> AppRoute? {
        let value = route
        route = nil
        return value
    }
}
