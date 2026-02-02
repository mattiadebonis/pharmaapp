import XCTest
import CoreData
@testable import PharmaApp

final class PrescriptionEventsTests: XCTestCase {
    func testPrescriptionReceivedIdempotent() throws {
        let container = try TestCoreDataFactory.makeContainer()
        let context = container.viewContext
        let medicine = try TestCoreDataFactory.makeMedicine(context: context)
        medicine.obbligo_ricetta = true
        let package = try TestCoreDataFactory.makePackage(context: context, medicine: medicine)
        try context.save()

        let useCase = RecordPrescriptionReceivedUseCase(
            eventStore: CoreDataEventStore(context: context),
            clock: SystemClock()
        )
        let operationId = UUID()
        let request = RecordPrescriptionReceivedRequest(
            operationId: operationId,
            medicineId: MedicineId(medicine.id),
            packageId: PackageId(package.id)
        )

        _ = try useCase.execute(request)
        _ = try useCase.execute(request)

        let logs = try TestCoreDataFactory.fetchLogs(context: context, operationId: operationId)
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(medicine.effectivePrescriptionReceivedLogs().count, 1)
    }
}
