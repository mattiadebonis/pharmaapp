import XCTest
import CoreData
@testable import PharmaApp

final class CabinetViewModelFavoritesOrderingTests: XCTestCase {
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

    func testPrioritizeFavoriteMedicinesMovesPinnedEntriesFirstPreservingRelativeOrder() throws {
        let regularMedicineA = try TestCoreDataFactory.makeMedicine(context: context)
        let regularPackageA = try TestCoreDataFactory.makePackage(context: context, medicine: regularMedicineA)
        let regularEntryA = try TestCoreDataFactory.makeMedicinePackage(
            context: context,
            medicine: regularMedicineA,
            package: regularPackageA
        )

        let pinnedMedicineA = try TestCoreDataFactory.makeMedicine(context: context)
        let pinnedPackageA = try TestCoreDataFactory.makePackage(context: context, medicine: pinnedMedicineA)
        let pinnedEntryA = try TestCoreDataFactory.makeMedicinePackage(
            context: context,
            medicine: pinnedMedicineA,
            package: pinnedPackageA
        )

        let regularMedicineB = try TestCoreDataFactory.makeMedicine(context: context)
        let regularPackageB = try TestCoreDataFactory.makePackage(context: context, medicine: regularMedicineB)
        let regularEntryB = try TestCoreDataFactory.makeMedicinePackage(
            context: context,
            medicine: regularMedicineB,
            package: regularPackageB
        )

        let pinnedMedicineB = try TestCoreDataFactory.makeMedicine(context: context)
        let pinnedPackageB = try TestCoreDataFactory.makePackage(context: context, medicine: pinnedMedicineB)
        let pinnedEntryB = try TestCoreDataFactory.makeMedicinePackage(
            context: context,
            medicine: pinnedMedicineB,
            package: pinnedPackageB
        )

        let ordered = CabinetViewModel().prioritizeFavoriteMedicines(
            [regularEntryA, pinnedEntryA, regularEntryB, pinnedEntryB],
            favoriteMedicineIDs: [pinnedMedicineA.id, pinnedMedicineB.id]
        )

        XCTAssertEqual(
            ordered.map(\.objectID),
            [
                pinnedEntryA.objectID,
                pinnedEntryB.objectID,
                regularEntryA.objectID,
                regularEntryB.objectID
            ]
        )
    }
}
