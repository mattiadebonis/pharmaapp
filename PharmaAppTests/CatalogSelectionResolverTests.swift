import XCTest
import CoreData
@testable import PharmaApp

final class CatalogSelectionResolverTests: XCTestCase {
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

    func testAddToCabinetCreatesMedicinePackageAndSetsFlag() throws {
        let resolver = CatalogSelectionResolver(context: context)
        let selection = CatalogSelection(
            id: "pkg-1",
            name: "Tachipirina",
            principle: "Paracetamolo",
            requiresPrescription: false,
            packageLabel: "20 compresse 500 mg",
            units: 20,
            tipologia: "20 compresse 500 mg",
            valore: 500,
            unita: "mg",
            volume: ""
        )

        let resolved = try resolver.addToCabinet(selection)

        XCTAssertTrue(resolved.medicine.in_cabinet)
        XCTAssertEqual(resolved.medicine.nome, "Tachipirina")
        XCTAssertEqual(Int(resolved.package.numero), 20)
        XCTAssertEqual(resolved.entry.medicine.objectID, resolved.medicine.objectID)
        XCTAssertEqual(resolved.entry.package.objectID, resolved.package.objectID)
        XCTAssertNil(resolved.entry.cabinet)
    }

    func testBuyOnePackageRegistersPurchaseAndIncrementsStock() throws {
        let resolver = CatalogSelectionResolver(context: context)
        let selection = CatalogSelection(
            id: "pkg-2",
            name: "Moment",
            principle: "Ibuprofene",
            requiresPrescription: false,
            packageLabel: "12 compresse 200 mg",
            units: 12,
            tipologia: "12 compresse 200 mg",
            valore: 200,
            unita: "mg",
            volume: ""
        )

        let resolved = try resolver.buyOnePackage(selection)
        let units = StockService(context: context).units(for: resolved.package)

        XCTAssertTrue(resolved.medicine.in_cabinet)
        XCTAssertEqual(units, 12)
        XCTAssertEqual(resolved.medicine.effectivePurchaseLogs().count, 1)
        XCTAssertEqual(resolved.medicine.effectivePurchaseLogs().first?.package?.objectID, resolved.package.objectID)
    }

    func testPrepareTherapyReusesExistingEntitiesWithNormalizedNameAndPrinciple() throws {
        let medicine = try TestCoreDataFactory.makeMedicine(context: context)
        medicine.nome = "Tachi-Pirina"
        medicine.principio_attivo = "Paracetamolo"
        medicine.in_cabinet = false

        let package = try TestCoreDataFactory.makePackage(context: context, medicine: medicine, numero: 20)
        package.tipologia = "20 compresse 500 mg"
        package.valore = 500
        package.unita = "mg"
        package.volume = ""

        let cabinet = try TestCoreDataFactory.makeCabinet(context: context, name: "Borsa")
        let entry = try TestCoreDataFactory.makeMedicinePackage(
            context: context,
            medicine: medicine,
            package: package,
            cabinet: cabinet
        )
        try context.save()

        let resolver = CatalogSelectionResolver(context: context)
        let selection = CatalogSelection(
            id: "pkg-3",
            name: "tachi pirina",
            principle: "PARACETAMOLO",
            requiresPrescription: false,
            packageLabel: "20 compresse 500 mg",
            units: 20,
            tipologia: "20 compresse 500 mg",
            valore: 500,
            unita: "mg",
            volume: ""
        )

        let resolved = try resolver.prepareTherapy(selection)

        XCTAssertEqual(resolved.medicine.objectID, medicine.objectID)
        XCTAssertEqual(resolved.package.objectID, package.objectID)
        XCTAssertEqual(resolved.entry.objectID, entry.objectID)
        XCTAssertTrue(resolved.medicine.in_cabinet)
        XCTAssertNil(resolved.entry.cabinet)
    }
}
