import XCTest
import CoreData
@testable import PharmaApp

final class CabinetViewModelSearchTests: XCTestCase {
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

    func testSearchEntriesIncludesOnlyMedicinesInCabinet() throws {
        let inCabinetMedicine = try TestCoreDataFactory.makeMedicine(context: context)
        inCabinetMedicine.nome = "Tachipirina"
        inCabinetMedicine.principio_attivo = "Paracetamolo"
        inCabinetMedicine.in_cabinet = true
        let inCabinetPackage = try TestCoreDataFactory.makePackage(context: context, medicine: inCabinetMedicine, numero: 20)
        let inCabinetEntry = try TestCoreDataFactory.makeMedicinePackage(
            context: context,
            medicine: inCabinetMedicine,
            package: inCabinetPackage
        )

        let outMedicine = try TestCoreDataFactory.makeMedicine(context: context)
        outMedicine.nome = "Tachifludec"
        outMedicine.principio_attivo = "Paracetamolo"
        outMedicine.in_cabinet = false
        let outPackage = try TestCoreDataFactory.makePackage(context: context, medicine: outMedicine, numero: 10)
        _ = try TestCoreDataFactory.makeMedicinePackage(
            context: context,
            medicine: outMedicine,
            package: outPackage
        )

        let results = CabinetViewModel().searchEntries(
            query: "tachi",
            entries: try context.fetch(MedicinePackage.extractEntries()),
            option: nil
        )

        XCTAssertEqual(results.map(\.objectID), [inCabinetEntry.objectID])
    }

    func testSearchEntriesMatchesPackageSummary() throws {
        let medicine = try TestCoreDataFactory.makeMedicine(context: context)
        medicine.nome = "Moment"
        medicine.principio_attivo = "Ibuprofene"
        medicine.in_cabinet = true

        let package = try TestCoreDataFactory.makePackage(context: context, medicine: medicine, numero: 24)
        package.tipologia = "sciroppo"
        package.valore = 250
        package.unita = "mg"
        package.volume = "100 ml"

        let entry = try TestCoreDataFactory.makeMedicinePackage(
            context: context,
            medicine: medicine,
            package: package
        )

        let results = CabinetViewModel().searchEntries(
            query: "100 ml",
            entries: [entry],
            option: nil
        )

        XCTAssertEqual(results.map(\.objectID), [entry.objectID])
    }
}
