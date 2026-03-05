import XCTest
import CoreData
@testable import PharmaApp

final class StockServicePurchaseEntryTests: XCTestCase {
    private var container: NSPersistentContainer!
    private var context: NSManagedObjectContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try TestCoreDataFactory.makeContainer()
        context = container.viewContext
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
        try super.tearDownWithError()
    }

    func testPurchaseCreatesEntryWithPurchaseOperationId() throws {
        let stockService = StockService(context: context)
        let medicine = try TestCoreDataFactory.makeMedicine(context: context)
        let package = try TestCoreDataFactory.makePackage(context: context, medicine: medicine)
        let purchaseOperationId = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

        let log = stockService.createLog(
            type: "purchase",
            medicine: medicine,
            package: package,
            timestamp: timestamp,
            operationId: purchaseOperationId
        )

        XCTAssertNotNil(log)
        let entries = try fetchEntries(medicine: medicine, package: package)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].purchase_operation_id, purchaseOperationId)
        XCTAssertEqual(entries[0].reversed_by_operation_id, nil)
        XCTAssertEqual(entries[0].created_at, timestamp)
    }

    func testPurchaseUndoMarksOnlyMatchingPurchasedEntryAsReversed() throws {
        let stockService = StockService(context: context)
        let medicine = try TestCoreDataFactory.makeMedicine(context: context)
        let package = try TestCoreDataFactory.makePackage(context: context, medicine: medicine)
        let firstPurchaseOperationId = UUID()
        let secondPurchaseOperationId = UUID()
        let undoOperationId = UUID()

        _ = stockService.createLog(
            type: "purchase",
            medicine: medicine,
            package: package,
            operationId: firstPurchaseOperationId
        )
        _ = stockService.createLog(
            type: "purchase",
            medicine: medicine,
            package: package,
            operationId: secondPurchaseOperationId
        )

        _ = stockService.createLog(
            type: "purchase_undo",
            medicine: medicine,
            package: package,
            operationId: undoOperationId,
            reversalOfOperationId: firstPurchaseOperationId
        )

        let firstEntry = try requireEntry(operationId: firstPurchaseOperationId)
        let secondEntry = try requireEntry(operationId: secondPurchaseOperationId)

        XCTAssertEqual(firstEntry.reversed_by_operation_id, undoOperationId)
        XCTAssertNil(secondEntry.reversed_by_operation_id)
    }

    func testDuplicatePurchaseOperationIdDoesNotCreateDuplicateEntries() throws {
        let stockService = StockService(context: context)
        let medicine = try TestCoreDataFactory.makeMedicine(context: context)
        let package = try TestCoreDataFactory.makePackage(context: context, medicine: medicine)
        let sharedOperationId = UUID()

        let firstLog = stockService.createLog(
            type: "purchase",
            medicine: medicine,
            package: package,
            operationId: sharedOperationId
        )
        let secondLog = stockService.createLog(
            type: "purchase",
            medicine: medicine,
            package: package,
            operationId: sharedOperationId
        )

        XCTAssertNotNil(firstLog)
        XCTAssertNotNil(secondLog)
        XCTAssertEqual(firstLog?.objectID, secondLog?.objectID)

        let entries = try fetchEntries(medicine: medicine, package: package)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].purchase_operation_id, sharedOperationId)

        let logs = try TestCoreDataFactory.fetchLogs(context: context, operationId: sharedOperationId)
        XCTAssertEqual(logs.count, 1)
    }

    private func fetchEntries(medicine: Medicine, package: Package) throws -> [MedicinePackage] {
        let request: NSFetchRequest<MedicinePackage> = MedicinePackage.fetchRequest() as! NSFetchRequest<MedicinePackage>
        request.sortDescriptors = [NSSortDescriptor(key: "created_at", ascending: true)]
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "medicine == %@", medicine),
            NSPredicate(format: "package == %@", package)
        ])
        return try context.fetch(request)
    }

    private func requireEntry(operationId: UUID) throws -> MedicinePackage {
        guard let entry = MedicinePackage.fetchByPurchaseOperationId(operationId, in: context) else {
            throw NSError(
                domain: "StockServicePurchaseEntryTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing purchase entry for operation \(operationId)"]
            )
        }
        return entry
    }
}
