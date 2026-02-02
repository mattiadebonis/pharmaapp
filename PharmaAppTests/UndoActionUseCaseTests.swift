import XCTest
import CoreData
@testable import PharmaApp

final class UndoActionUseCaseTests: XCTestCase {
    func testUndoPrescriptionReceivedCreatesReversalAndBlocksState() throws {
        let container = try TestCoreDataFactory.makeContainer()
        let context = container.viewContext
        let medicine = try TestCoreDataFactory.makeMedicine(context: context)
        medicine.obbligo_ricetta = true
        let package = try TestCoreDataFactory.makePackage(context: context, medicine: medicine)
        try context.save()

        let recordUseCase = RecordPrescriptionReceivedUseCase(
            eventStore: CoreDataEventStore(context: context),
            clock: SystemClock()
        )
        let operationId = UUID()
        let recordRequest = RecordPrescriptionReceivedRequest(
            operationId: operationId,
            medicineId: MedicineId(medicine.id),
            packageId: PackageId(package.id)
        )
        _ = try recordUseCase.execute(recordRequest)

        let undoUseCase = UndoActionUseCase(
            eventStore: CoreDataEventStore(context: context),
            clock: SystemClock()
        )
        let undoRequest = UndoActionRequest(
            originalOperationId: operationId,
            undoOperationId: UUID()
        )
        _ = try undoUseCase.execute(undoRequest)

        let undoFetch: NSFetchRequest<Log> = Log.fetchRequest() as! NSFetchRequest<Log>
        undoFetch.predicate = NSPredicate(format: "type == 'prescription_received_undo'")
        let undoLogs = try context.fetch(undoFetch)

        XCTAssertEqual(undoLogs.count, 1)
        XCTAssertEqual(undoLogs.first?.reversal_of_operation_id, operationId)
        XCTAssertEqual(medicine.effectivePrescriptionReceivedLogs().count, 0)

        let recManager = RecurrenceManager(context: context)
        XCTAssertTrue(TodayTodoEngine.needsPrescriptionBeforePurchase(medicine, option: nil, recurrenceManager: recManager))
    }
}
