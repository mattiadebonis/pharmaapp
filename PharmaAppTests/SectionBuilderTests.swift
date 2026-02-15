import XCTest
import CoreData
@testable import PharmaApp

final class SectionBuilderTests: XCTestCase {
    private var container: NSPersistentContainer!
    private var context: NSManagedObjectContext!

    override func setUpWithError() throws {
        container = try TestCoreDataFactory.makeContainer()
        context = container.viewContext
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
    }

    func testComputeSectionsOrdersPurchaseTodayAndOkDeterministically() throws {
        let stockService = StockService(context: context)

        let criticalMedicine = try TestCoreDataFactory.makeMedicine(context: context)
        criticalMedicine.nome = "Critical"
        let criticalPackage = try TestCoreDataFactory.makePackage(context: context, medicine: criticalMedicine)
        stockService.setUnits(0, for: criticalPackage)

        let lowMedicine = try TestCoreDataFactory.makeMedicine(context: context)
        lowMedicine.nome = "Low"
        let lowPackage = try TestCoreDataFactory.makePackage(context: context, medicine: lowMedicine)
        stockService.setUnits(2, for: lowPackage)

        let todayMedicine = try TestCoreDataFactory.makeMedicine(context: context)
        todayMedicine.nome = "Today"
        let todayPackage = try TestCoreDataFactory.makePackage(context: context, medicine: todayMedicine)
        stockService.setUnits(30, for: todayPackage)
        _ = try makeDailyTherapy(medicine: todayMedicine, package: todayPackage, hour: 9)

        let okMedicine = try TestCoreDataFactory.makeMedicine(context: context)
        okMedicine.nome = "Ok"
        let okPackage = try TestCoreDataFactory.makePackage(context: context, medicine: okMedicine)
        stockService.setUnits(30, for: okPackage)

        try context.save()

        let sections = computeSections(
            for: [okMedicine, todayMedicine, lowMedicine, criticalMedicine],
            logs: [],
            option: nil
        )

        XCTAssertEqual(sections.purchase.map(\.nome), ["Critical", "Low"])
        XCTAssertEqual(sections.oggi.map(\.nome), ["Today"])
        XCTAssertEqual(sections.ok.map(\.nome), ["Ok"])
    }

    func testComputeSectionsHandlesMedicinesWithAndWithoutTherapies() throws {
        let stockService = StockService(context: context)

        let plainMedicine = try TestCoreDataFactory.makeMedicine(context: context)
        plainMedicine.nome = "NoTherapy"
        let plainPackage = try TestCoreDataFactory.makePackage(context: context, medicine: plainMedicine)
        stockService.setUnits(20, for: plainPackage)

        let therapyMedicine = try TestCoreDataFactory.makeMedicine(context: context)
        therapyMedicine.nome = "WithTherapy"
        let therapyPackage = try TestCoreDataFactory.makePackage(context: context, medicine: therapyMedicine)
        stockService.setUnits(20, for: therapyPackage)
        _ = try makeDailyTherapy(medicine: therapyMedicine, package: therapyPackage, hour: 10)

        try context.save()

        let sections = computeSections(
            for: [plainMedicine, therapyMedicine],
            logs: [],
            option: nil
        )

        XCTAssertTrue(sections.purchase.isEmpty)
        XCTAssertEqual(sections.oggi.map(\.nome), ["WithTherapy"])
        XCTAssertEqual(sections.ok.map(\.nome), ["NoTherapy"])
    }

    func testComputeSectionsOkTieBreakUsesDeadlineThenName() throws {
        let stockService = StockService(context: context)

        let beta = try TestCoreDataFactory.makeMedicine(context: context)
        beta.nome = "Beta"
        beta.deadline_month = 5
        beta.deadline_year = 2027
        let betaPackage = try TestCoreDataFactory.makePackage(context: context, medicine: beta)
        stockService.setUnits(20, for: betaPackage)

        let alpha = try TestCoreDataFactory.makeMedicine(context: context)
        alpha.nome = "Alpha"
        alpha.deadline_month = 4
        alpha.deadline_year = 2027
        let alphaPackage = try TestCoreDataFactory.makePackage(context: context, medicine: alpha)
        stockService.setUnits(20, for: alphaPackage)

        let gamma = try TestCoreDataFactory.makeMedicine(context: context)
        gamma.nome = "Gamma"
        gamma.deadline_month = 4
        gamma.deadline_year = 2027
        let gammaPackage = try TestCoreDataFactory.makePackage(context: context, medicine: gamma)
        stockService.setUnits(20, for: gammaPackage)

        try context.save()

        let sections = computeSections(for: [beta, gamma, alpha], logs: [], option: nil)

        XCTAssertEqual(sections.purchase.count, 0)
        XCTAssertEqual(sections.oggi.count, 0)
        XCTAssertEqual(sections.ok.map(\.nome), ["Alpha", "Gamma", "Beta"])
    }

    private func makeDailyTherapy(medicine: Medicine, package: Package, hour: Int) throws -> Therapy {
        let therapy = try TestCoreDataFactory.makeTherapy(context: context, medicine: medicine)
        therapy.package = package
        therapy.start_date = Calendar.current.date(byAdding: .day, value: -1, to: Date())
        therapy.rrule = "RRULE:FREQ=DAILY"

        let personEntity = try requireEntity(named: "Person")
        let person = Person(entity: personEntity, insertInto: context)
        person.id = UUID()
        person.nome = "Test"
        therapy.person = person

        let doseEntity = try requireEntity(named: "Dose")
        let dose = Dose(entity: doseEntity, insertInto: context)
        dose.id = UUID()
        dose.amount = NSNumber(value: 1.0)
        dose.time = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        dose.therapy = therapy
        therapy.doses = [dose]

        return therapy
    }

    private func requireEntity(named name: String) throws -> NSEntityDescription {
        guard let entity = NSEntityDescription.entity(forEntityName: name, in: context) else {
            throw NSError(domain: "SectionBuilderTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing entity: \(name)"])
        }
        return entity
    }
}
