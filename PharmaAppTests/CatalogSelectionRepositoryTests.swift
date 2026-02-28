import XCTest
import CoreData
@testable import PharmaApp

final class CatalogSelectionRepositoryTests: XCTestCase {
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

    func testSearchSelectionsExcludesMedicinesAlreadyInCabinet() throws {
        let medicine = try TestCoreDataFactory.makeMedicine(context: context)
        medicine.nome = "Tachipirina"
        medicine.principio_attivo = "Paracetamolo"
        medicine.in_cabinet = true

        let repository = CatalogSelectionRepository()
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

        let results = repository.searchSelections(
            query: "tachi",
            in: [selection],
            excludingIdentityKeys: repository.inCabinetIdentityKeys(from: [medicine])
        )

        XCTAssertTrue(results.isEmpty)
    }

    func testSearchSelectionsKeepsMedicinesWithEntriesButFlagFalseOutOfCabinet() throws {
        let medicine = try TestCoreDataFactory.makeMedicine(context: context)
        medicine.nome = "Tachipirina"
        medicine.principio_attivo = "Paracetamolo"
        medicine.in_cabinet = false

        let package = try TestCoreDataFactory.makePackage(context: context, medicine: medicine, numero: 20)
        _ = try TestCoreDataFactory.makeMedicinePackage(
            context: context,
            medicine: medicine,
            package: package
        )

        let repository = CatalogSelectionRepository()
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

        let results = repository.searchSelections(
            query: "tachi",
            in: [selection],
            excludingIdentityKeys: repository.inCabinetIdentityKeys(from: [medicine])
        )

        XCTAssertEqual(results.map(\.id), ["pkg-1"])
    }
}
