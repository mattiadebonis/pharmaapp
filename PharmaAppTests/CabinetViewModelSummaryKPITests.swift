import XCTest
import CoreData
@testable import PharmaApp

final class CabinetViewModelSummaryKPITests: XCTestCase {
    private var container: NSPersistentContainer!
    private var context: NSManagedObjectContext!
    private var viewModel: CabinetViewModel!

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try TestCoreDataFactory.makeContainer()
        context = container.viewContext
        viewModel = CabinetViewModel()
    }

    override func tearDownWithError() throws {
        viewModel = nil
        context = nil
        container = nil
        try super.tearDownWithError()
    }

    func testSummaryKPIAllCoveredShowsFullCoverage() throws {
        let first = try makeMedicine(name: "Aspirina", stockUnits: 10)
        let second = try makeMedicine(name: "Ibuprofene", stockUnits: 12)

        let display = viewModel.computeSummaryDisplayData(
            medicines: [first.medicine, second.medicine],
            option: nil,
            pharmacy: nil
        )

        XCTAssertEqual(display.kpi.coveredCount, 2)
        XCTAssertEqual(display.kpi.totalCount, 2)
        XCTAssertEqual(display.kpi.stockStatusText, "Sotto controllo")
        XCTAssertNil(display.kpi.stockStatusDetailText)
        XCTAssertEqual(display.kpi.stockStatusTone, .success)
        XCTAssertEqual(display.kpi.refillCount, 0)
        XCTAssertNil(display.kpi.nextRefillInDays)
        XCTAssertEqual(display.lines, ["2 su 2", "farmaci coperti"])
        XCTAssertEqual(display.inlineAction, "Scorte 2/2")
    }

    func testSummaryKPIOneLowStockReducesCoverage() throws {
        let first = try makeMedicine(name: "Aspirina", stockUnits: 10)
        let second = try makeMedicine(name: "Ibuprofene", stockUnits: 2)

        let display = viewModel.computeSummaryDisplayData(
            medicines: [first.medicine, second.medicine],
            option: nil,
            pharmacy: nil
        )

        XCTAssertEqual(display.kpi.coveredCount, 1)
        XCTAssertEqual(display.kpi.totalCount, 2)
        XCTAssertEqual(display.kpi.stockStatusText, "Attenzione")
        XCTAssertEqual(display.kpi.stockStatusDetailText, "1 farmaco da rifornire · prossimo da verificare")
        XCTAssertEqual(display.kpi.stockStatusTone, .warning)
        XCTAssertEqual(display.kpi.refillCount, 1)
        XCTAssertNil(display.kpi.nextRefillInDays)
        XCTAssertEqual(display.lines, ["1 su 2", "farmaci coperti"])
        XCTAssertEqual(display.inlineAction, "Scorte 1/2")
    }

    func testSummaryKPIUnknownStockCountsAsNotCovered() throws {
        let item = try makeMedicine(name: "Vitamina", stockUnits: 0)
        try attachTherapy(
            medicine: item.medicine,
            package: item.package,
            rrule: "",
            stockUnits: 0
        )

        let snapshot = CoreDataSnapshotBuilder(context: context)
            .makeMedicineSnapshot(medicine: item.medicine, logs: [])
        let status = viewModel.sectionCalculator.stockStatus(for: snapshot, option: nil)
        XCTAssertEqual(status, .unknown)

        let display = viewModel.computeSummaryDisplayData(
            medicines: [item.medicine],
            option: nil,
            pharmacy: nil
        )

        XCTAssertEqual(display.kpi.coveredCount, 0)
        XCTAssertEqual(display.kpi.totalCount, 1)
        XCTAssertEqual(display.kpi.stockStatusText, "Da verificare")
        XCTAssertNil(display.kpi.stockStatusDetailText)
        XCTAssertEqual(display.kpi.stockStatusTone, .warning)
        XCTAssertEqual(display.kpi.refillCount, 0)
        XCTAssertNil(display.kpi.nextRefillInDays)
        XCTAssertEqual(display.lines, ["0 su 1", "farmaci coperti"])
        XCTAssertEqual(display.inlineAction, "Scorte 0/1")
    }

    func testSummaryKPIEmptyCabinetShowsZeroBalance() {
        let display = viewModel.computeSummaryDisplayData(
            medicines: [],
            option: nil,
            pharmacy: nil
        )

        XCTAssertEqual(display.kpi.coveredCount, 0)
        XCTAssertEqual(display.kpi.totalCount, 0)
        XCTAssertEqual(display.kpi.stockStatusText, "Vuoto")
        XCTAssertNil(display.kpi.stockStatusDetailText)
        XCTAssertEqual(display.kpi.stockStatusTone, .neutral)
        XCTAssertEqual(display.kpi.refillCount, 0)
        XCTAssertNil(display.kpi.nextRefillInDays)
        XCTAssertEqual(display.lines, ["0 su 0", "farmaci coperti"])
        XCTAssertEqual(display.inlineAction, "Scorte 0/0")
    }

    func testSummaryKPIRefillWithTherapyShowsNearestDays() throws {
        let item = try makeMedicine(name: "Moment", stockUnits: 2)
        try attachTherapy(
            medicine: item.medicine,
            package: item.package,
            rrule: "RRULE:FREQ=DAILY",
            stockUnits: 2
        )

        let display = viewModel.computeSummaryDisplayData(
            medicines: [item.medicine],
            option: nil,
            pharmacy: nil
        )

        XCTAssertEqual(display.kpi.stockStatusText, "Attenzione")
        XCTAssertEqual(display.kpi.stockStatusDetailText, "1 farmaco da rifornire · prossimo tra 2 giorni")
        XCTAssertEqual(display.kpi.stockStatusTone, .warning)
        XCTAssertEqual(display.kpi.refillCount, 1)
        XCTAssertEqual(display.kpi.nextRefillInDays, 2)
    }

    func testSummaryLinesIncludePharmacyOnlyForRefillPriority() throws {
        let item = try makeMedicine(name: "Terapia", stockUnits: 0)
        try attachTherapy(
            medicine: item.medicine,
            package: item.package,
            rrule: "RRULE:FREQ=DAILY",
            stockUnits: 0
        )

        let display = viewModel.computeSummaryDisplayData(
            medicines: [item.medicine],
            option: nil,
            pharmacy: PharmacyInfo(name: "Farmacia San Martino", isOpen: true, distanceText: "4 min")
        )

        XCTAssertTrue(display.summary.priority == .refillBeforeNextDose
            || display.summary.priority == .refillWithinToday
            || display.summary.priority == .refillSoon)
        XCTAssertEqual(display.lines.count, 3)
        XCTAssertEqual(display.lines[0], "0 su 1")
        XCTAssertEqual(display.lines[1], "farmaci coperti")
        XCTAssertTrue(display.lines[2].contains("Farmacia suggerita"))
        XCTAssertEqual(display.kpi.stockStatusText, "Critico")
        XCTAssertEqual(display.kpi.stockStatusDetailText, "1 farmaco da rifornire · prossimo oggi")
        XCTAssertEqual(display.kpi.stockStatusTone, .critical)
        XCTAssertEqual(display.kpi.refillCount, 1)
        XCTAssertEqual(display.kpi.nextRefillInDays, 0)
    }

    func testRowSnapshotHighlightsOnlyCoverageWhenTherapyIsBelowThreshold() throws {
        let item = try makeMedicine(name: "Tachipirina", stockUnits: 2)
        try attachTherapy(
            medicine: item.medicine,
            package: item.package,
            rrule: "RRULE:FREQ=DAILY",
            stockUnits: 2
        )

        let presentation = try XCTUnwrap(
            viewModel.buildRowSnapshots(entries: [item.entry], option: nil).values.first?.presentation
        )

        XCTAssertEqual(presentation.line1, "Copertura scorte: 2 giorni")
        XCTAssertEqual(presentation.line2, "Confezioni: 1 · Unità: 2")
        XCTAssertEqual(presentation.line1Tone, .danger)
        XCTAssertEqual(presentation.line2Tone, .normal)
    }

    func testRowSnapshotHighlightsCoverageAndStockWhenTherapyIsOutOfStock() throws {
        let item = try makeMedicine(name: "Tachipirina", stockUnits: 0)
        try attachTherapy(
            medicine: item.medicine,
            package: item.package,
            rrule: "RRULE:FREQ=DAILY",
            stockUnits: 0
        )

        let presentation = try XCTUnwrap(
            viewModel.buildRowSnapshots(entries: [item.entry], option: nil).values.first?.presentation
        )

        XCTAssertEqual(presentation.line1, "Copertura scorte: < 1 giorno")
        XCTAssertEqual(presentation.line2, "Confezioni: 0 · Unità: 0")
        XCTAssertEqual(presentation.line1Tone, .danger)
        XCTAssertEqual(presentation.line2Tone, .danger)
    }

    func testRowSnapshotHighlightsOnlyPackagesWhenMedicineHasNoTherapy() throws {
        let item = try makeMedicine(name: "Ibuprofene", stockUnits: 2)

        let presentation = try XCTUnwrap(
            viewModel.buildRowSnapshots(entries: [item.entry], option: nil).values.first?.presentation
        )

        XCTAssertEqual(presentation.line1, "1 confezione")
        XCTAssertEqual(presentation.line2, "")
        XCTAssertEqual(presentation.line1Tone, .danger)
        XCTAssertEqual(presentation.line2Tone, .normal)
    }

    func testSummaryLinesStayKPIOnlyOutsideRefillPriority() throws {
        let item = try makeMedicine(name: "Paracetamolo", stockUnits: 1)

        let display = viewModel.computeSummaryDisplayData(
            medicines: [item.medicine],
            option: nil,
            pharmacy: PharmacyInfo(name: "Farmacia Centro", isOpen: true, distanceText: "3 min")
        )

        XCTAssertEqual(display.summary.priority, .allUnderControl)
        XCTAssertEqual(display.lines, ["0 su 1", "farmaci coperti"])
    }

    private func makeMedicine(
        name: String,
        stockUnits: Int
    ) throws -> (medicine: Medicine, package: Package, entry: MedicinePackage) {
        let medicine = try TestCoreDataFactory.makeMedicine(context: context)
        medicine.nome = name
        medicine.in_cabinet = true

        let package = try TestCoreDataFactory.makePackage(
            context: context,
            medicine: medicine,
            numero: 20
        )
        let entry = try TestCoreDataFactory.makeMedicinePackage(
            context: context,
            medicine: medicine,
            package: package
        )

        StockService(context: context).setUnits(stockUnits, for: package)
        return (medicine, package, entry)
    }

    private func attachTherapy(
        medicine: Medicine,
        package: Package,
        rrule: String,
        stockUnits: Int
    ) throws {
        let therapy = try TestCoreDataFactory.makeTherapy(context: context, medicine: medicine)
        therapy.package = package
        therapy.person = try makePerson()
        therapy.start_date = Calendar.current.date(byAdding: .day, value: -1, to: Date())
        therapy.rrule = rrule
        therapy.manual_intake_registration = false

        guard let doseEntity = NSEntityDescription.entity(forEntityName: "Dose", in: context) else {
            throw NSError(
                domain: "CabinetViewModelSummaryKPITests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Dose entity not found"]
            )
        }
        let dose = Dose(entity: doseEntity, insertInto: context)
        dose.id = UUID()
        dose.time = Date()
        dose.amount = NSNumber(value: 1.0)
        dose.therapy = therapy
        therapy.doses = Set([dose])

        StockService(context: context).setUnits(stockUnits, for: package)
    }

    private func makePerson() throws -> Person {
        guard let entity = NSEntityDescription.entity(forEntityName: "Person", in: context) else {
            throw NSError(
                domain: "CabinetViewModelSummaryKPITests",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Person entity not found"]
            )
        }

        let person = Person(entity: entity, insertInto: context)
        person.id = UUID()
        person.nome = "Mario"
        person.cognome = "Rossi"
        return person
    }
}
