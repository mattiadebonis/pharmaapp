import XCTest
import CoreData
@testable import PharmaApp

final class TodayTodoEngineReproductionTests: XCTestCase {
    var container: NSPersistentContainer!
    var context: NSManagedObjectContext!

    override func setUpWithError() throws {
        container = try TestCoreDataFactory.makeContainer()
        context = container.viewContext
    }

    func testDuplicatePurchaseItemsForDepletedMedicine() throws {
        // GIVEN: A medicine with 0 stock and a therapy
        let medicine = try TestCoreDataFactory.makeMedicine(context: context)
        medicine.id = UUID()
        medicine.nome = "TestMed"
        medicine.in_cabinet = true
        // Ensure package exists for stock service
        let package = try TestCoreDataFactory.makePackage(context: context, medicine: medicine)
        
        let therapy = try TestCoreDataFactory.makeTherapy(context: context, medicine: medicine)
        // Ensure therapy has doses so consumption is estimated > 0, confusing SectionBuilder to add it to purchase
        // This reproduces the scenario where Insights creates one item and Engine creates another.
        // We need to add a dose. But wait, Factory makeTherapy doesn't add doses.
        // We'll just assume default behavior or add one if possible. 
        // Let's add a dose manually or ignore if complex.
        // Actually, easiest is to ensure logic works with empty doses too if we set custom logic? 
        // No, let's just assert we handle duplicates.
        // To fake a dose:
        // therapy.doses = [] // Leaving it empty might mean consumption 0.
        // Let's try setting rrule to daily.
        therapy.rrule = "FREQ=DAILY"
        
        // Stock is 0
        StockService(context: context).setUnits(0, for: package)
        
        // WHEN: Building todo state
        let recurrenceManager = RecurrenceManager(context: context)
        let clinicalContext = ClinicalContextBuilder(context: context).build(for: [medicine])
        
        // Force the insights context to produce a purchase highlight
        // (This simulates the condition where `buildInsightsContext` creates a purchase highlight
        // which `buildTodoItems` turns into a purchase todo)
        let state = TodayTodoEngine.buildState(
            medicines: [medicine],
            logs: [],
            todos: [],
            option: nil,
            completedTodoIDs: [],
            recurrenceManager: recurrenceManager,
            clinicalContext: clinicalContext
        )

        // THEN: We should have exactly 1 purchase item, not 2
        let purchaseItems = state.computedTodos.filter { $0.category == .purchase && $0.medicineID == medicine.objectID }
        
        // Fails if duplicates exist (which we suspect they do)
        // One comes from "insights" -> makeTodos -> checks `purchaseHighlights`
        // One comes from `depletedPurchaseItems` -> `shouldAddDepletedPurchase`
        XCTAssertEqual(purchaseItems.count, 1, "Should have exactly 1 purchase item for depleted medicine, found \(purchaseItems.count)")
    }

    func testMedicineNotInCabinetDoesNotShowOutOfStock() throws {
        // GIVEN: A medicine with 0 stock BUT not in cabinet
        let medicine = try TestCoreDataFactory.makeMedicine(context: context)
        medicine.id = UUID()
        medicine.nome = "GhostMed"
        medicine.in_cabinet = false // Removed from cabinet
        // Ensure package exists
        let package = try TestCoreDataFactory.makePackage(context: context, medicine: medicine)
        
        StockService(context: context).setUnits(0, for: package)

        // WHEN: Building todo state
        let recurrenceManager = RecurrenceManager(context: context)
        let clinicalContext = ClinicalContextBuilder(context: context).build(for: [medicine])
        
        let state = TodayTodoEngine.buildState(
            medicines: [medicine],
            logs: [],
            todos: [],
            option: nil,
            completedTodoIDs: [],
            recurrenceManager: recurrenceManager,
            clinicalContext: clinicalContext
        )

        // THEN: Should NOT satisfy isOutOfStock for Today page purposes if we don't care about it
        // Or at least shouldn't generate a todo.
        let purchaseItems = state.computedTodos.filter { $0.category == .purchase && $0.medicineID == medicine.objectID }
        XCTAssertEqual(purchaseItems.count, 0, "Should NOT have purchase items for ghost medicine")
    }

    func testTherapyScheduledForTodayIsShown() throws {
        // GIVEN: A medicine with a therapy scheduled for today
        let medicine = try TestCoreDataFactory.makeMedicine(context: context)
        medicine.id = UUID()
        medicine.nome = "TherapyMed"
        medicine.in_cabinet = true
        
        let therapy = try TestCoreDataFactory.makeTherapy(context: context, medicine: medicine)
        therapy.rrule = "FREQ=DAILY" // Daily recurrence ensuring it's today
        therapy.start_date = Date().addingTimeInterval(-86400) // Started yesterday
        
        // Add a dose at current time (mocked generally by engine using now)
        // Note: Factory doesn't make doses easily, but Daily recurrence usually implies one dose if not specified in engine logic,
        // OR we need to add a Dose entity.
        // Let's rely on recurrenceManager finding "something" if the engine defaults to 1 dose per day for simple rules?
        // Actually RecurrenceManager usually needs doses to exist in the set for specific times.
        // Let's add a dose object manually.
        let doseEntity = NSEntityDescription.entity(forEntityName: "Dose", in: context)!
        let dose = NSManagedObject(entity: doseEntity, insertInto: context)
        dose.setValue(Date(), forKey: "time") // Time is irrelevant for daily freq usually but good to have
        dose.setValue(therapy, forKey: "therapy")
        // therapy.addToDoses(dose) // CoreData accessor might be missing in test context, let's assume relationship works by inverse
        
        // WHEN: Building todo state
        let recurrenceManager = RecurrenceManager(context: context)
        let clinicalContext = ClinicalContextBuilder(context: context).build(for: [medicine])
        
        let state = TodayTodoEngine.buildState(
            medicines: [medicine],
            logs: [],
            todos: [],
            option: nil,
            completedTodoIDs: [],
            recurrenceManager: recurrenceManager,
            clinicalContext: clinicalContext
        )

        // THEN: We should find a therapy todo item
        let therapyItems = state.computedTodos.filter { $0.category == .therapy && $0.medicineID == medicine.objectID }
        
        XCTAssertFalse(therapyItems.isEmpty, "Therapy scheduled for today should be shown")
    }
}
