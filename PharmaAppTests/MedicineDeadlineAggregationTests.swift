import XCTest
import CoreData
@testable import PharmaApp

final class MedicineDeadlineAggregationTests: XCTestCase {
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

    func testDeadlineMonthYearUsesNearestActiveEntryDeadline() throws {
        let medicine = try TestCoreDataFactory.makeMedicine(context: context)
        medicine.deadline_month = 11
        medicine.deadline_year = 2035
        let package = try TestCoreDataFactory.makePackage(context: context, medicine: medicine)

        let nearEntry = try TestCoreDataFactory.makeMedicinePackage(
            context: context,
            medicine: medicine,
            package: package
        )
        nearEntry.updateDeadline(month: 4, year: 2028)

        let farEntry = try TestCoreDataFactory.makeMedicinePackage(
            context: context,
            medicine: medicine,
            package: package
        )
        farEntry.updateDeadline(month: 8, year: 2028)

        let reversedSoonEntry = try TestCoreDataFactory.makeMedicinePackage(
            context: context,
            medicine: medicine,
            package: package
        )
        reversedSoonEntry.updateDeadline(month: 1, year: 2028)
        reversedSoonEntry.purchase_operation_id = UUID()
        reversedSoonEntry.reversed_by_operation_id = UUID()

        try context.save()

        XCTAssertEqual(medicine.deadlineMonthYear?.month, 4)
        XCTAssertEqual(medicine.deadlineMonthYear?.year, 2028)
    }

    func testDeadlineMonthYearFallsBackToLegacyWhenNoEntryHasDeadline() throws {
        let medicine = try TestCoreDataFactory.makeMedicine(context: context)
        medicine.deadline_month = 9
        medicine.deadline_year = 2032
        let package = try TestCoreDataFactory.makePackage(context: context, medicine: medicine)

        _ = try TestCoreDataFactory.makeMedicinePackage(
            context: context,
            medicine: medicine,
            package: package
        )

        try context.save()

        XCTAssertEqual(medicine.deadlineMonthYear?.month, 9)
        XCTAssertEqual(medicine.deadlineMonthYear?.year, 2032)
    }
}
