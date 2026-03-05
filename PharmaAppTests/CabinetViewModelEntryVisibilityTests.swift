import XCTest
import CoreData
@testable import PharmaApp

final class CabinetViewModelEntryVisibilityTests: XCTestCase {
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

    func testShelfViewStateHidesPlaceholderWhenPurchasedEntryExistsForSamePair() throws {
        let medicine = try TestCoreDataFactory.makeMedicine(context: context)
        medicine.nome = "Test"
        let package = try TestCoreDataFactory.makePackage(context: context, medicine: medicine)

        let placeholder = try TestCoreDataFactory.makeMedicinePackage(
            context: context,
            medicine: medicine,
            package: package
        )

        let purchased = try TestCoreDataFactory.makeMedicinePackage(
            context: context,
            medicine: medicine,
            package: package
        )
        purchased.purchase_operation_id = UUID()
        purchased.created_at = Date().addingTimeInterval(30)

        try context.save()

        let state = CabinetViewModel().shelfViewState(
            entries: [placeholder, purchased],
            option: nil,
            cabinets: []
        )

        let visibleIDs = state.entries.compactMap { shelfEntry -> NSManagedObjectID? in
            if case .medicinePackage(let entry) = shelfEntry.kind {
                return entry.objectID
            }
            return nil
        }

        XCTAssertEqual(visibleIDs, [purchased.objectID])
    }
}
