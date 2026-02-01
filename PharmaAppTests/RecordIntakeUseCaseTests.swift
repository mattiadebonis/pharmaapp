import XCTest
import CoreData
@testable import PharmaApp

final class RecordIntakeUseCaseTests: XCTestCase {
    private struct FixedClock: Clock {
        let date: Date
        func now() -> Date { date }
    }

    private final class FailingSaveContext: NSManagedObjectContext {
        var shouldFailSave = false

        override func save() throws {
            if shouldFailSave {
                throw NSError(domain: "RecordIntakeUseCaseTests", code: 1, userInfo: nil)
            }
            try super.save()
        }
    }

    private func makeModel() throws -> NSManagedObjectModel {
        let bundles = [Bundle.main, Bundle(for: Medicine.self)]
        if let model = NSManagedObjectModel.mergedModel(from: bundles),
           model.entitiesByName["Medicine"] != nil {
            return model
        }
        let bundle = Bundle(for: Medicine.self)
        if let url = bundle.url(forResource: "PharmaApp", withExtension: "momd"),
           let model = NSManagedObjectModel(contentsOf: url),
           model.entitiesByName["Medicine"] != nil {
            return model
        }
        throw NSError(domain: "RecordIntakeUseCaseTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing Medicine entity in PharmaApp model"])
    }

    private func makeContainer() throws -> NSPersistentContainer {
        let model = try makeModel()
        let container = NSPersistentContainer(name: "PharmaApp", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.url = URL(fileURLWithPath: "/dev/null")
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        container.loadPersistentStores { _, error in
            loadError = error
            semaphore.signal()
        }
        semaphore.wait()
        if let loadError { throw loadError }
        guard let entities = container.viewContext.persistentStoreCoordinator?.managedObjectModel.entitiesByName,
              entities["Medicine"] != nil,
              entities["Package"] != nil,
              entities["Log"] != nil,
              entities["Stock"] != nil else {
            throw NSError(domain: "RecordIntakeUseCaseTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Required entities missing from context model"])
        }
        let context = container.viewContext
        let requiredEntityNames = ["Medicine", "Package", "Log", "Stock"]
        for name in requiredEntityNames {
            if NSEntityDescription.entity(forEntityName: name, in: context) == nil {
                throw NSError(domain: "RecordIntakeUseCaseTests", code: 6, userInfo: [NSLocalizedDescriptionKey: "Entity \(name) not resolved in context"])
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        return container
    }

    private func makeMedicine(context: NSManagedObjectContext, id: UUID = UUID()) throws -> Medicine {
        guard let entity = NSEntityDescription.entity(forEntityName: "Medicine", in: context) else {
            throw NSError(domain: "RecordIntakeUseCaseTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Medicine entity not found"])
        }
        let medicine = Medicine(entity: entity, insertInto: context)
        medicine.id = id
        medicine.nome = "Test"
        medicine.principio_attivo = "Test"
        medicine.obbligo_ricetta = false
        medicine.flag_alcol = false
        medicine.flag_potassio = false
        medicine.flag_guida = false
        medicine.flag_dopante = false
        medicine.carente = false
        medicine.innovativo = false
        medicine.orfano = false
        medicine.revocato = false
        medicine.sospeso = false
        medicine.flag_fi = false
        medicine.flag_rcp = false
        medicine.aic6 = 0
        medicine.codice_sis = 0
        medicine.categoria_medicinale = 0
        medicine.custom_stock_threshold = 0
        medicine.deadline_month = 0
        medicine.deadline_year = 0
        medicine.manual_intake_registration = false
        medicine.safety_max_per_day = 0
        medicine.safety_min_interval_hours = 0
        medicine.in_cabinet = false
        medicine.packages = []
        return medicine
    }

    private func makePackage(
        context: NSManagedObjectContext,
        id: UUID = UUID(),
        medicine: Medicine,
        numero: Int32 = 10
    ) throws -> Package {
        guard let entity = NSEntityDescription.entity(forEntityName: "Package", in: context) else {
            throw NSError(domain: "RecordIntakeUseCaseTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Package entity not found"])
        }
        let package = Package(entity: entity, insertInto: context)
        package.id = id
        package.numero = numero
        package.tipologia = "std"
        package.valore = 0
        package.unita = "u"
        package.volume = "0"
        package.medicine = medicine
        medicine.packages = [package]
        return package
    }

    private func fetchLogs(context: NSManagedObjectContext, operationId: UUID) throws -> [Log] {
        let request: NSFetchRequest<Log> = Log.fetchRequest() as! NSFetchRequest<Log>
        request.predicate = NSPredicate(format: "operation_id == %@", operationId as CVarArg)
        return try context.fetch(request)
    }

    func testRecordIntakeIdempotent() throws {
        let container = try makeContainer()
        let context = container.viewContext
        let medicine = try makeMedicine(context: context)
        let package = try makePackage(context: context, medicine: medicine)
        try context.save()

        let stockService = StockService(context: context)
        _ = stockService.createLog(
            type: "purchase",
            medicine: medicine,
            package: package,
            operationId: UUID()
        )
        let initialUnits = stockService.units(for: package)

        let useCase = RecordIntakeUseCase(
            eventStore: CoreDataEventStore(context: context),
            clock: FixedClock(date: Date())
        )
        let operationId = UUID()
        let request = RecordIntakeRequest(
            operationId: operationId,
            medicineId: MedicineId(medicine.id),
            therapyId: nil,
            packageId: PackageId(package.id)
        )

        _ = try useCase.execute(request)
        _ = try useCase.execute(request)

        let logs = try fetchLogs(context: context, operationId: operationId)
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(stockService.units(for: package), initialUnits - 1)
    }

    func testUndoCreatesReversalAndRestoresStock() throws {
        let container = try makeContainer()
        let context = container.viewContext
        let medicine = try makeMedicine(context: context)
        let package = try makePackage(context: context, medicine: medicine)
        try context.save()

        let stockService = StockService(context: context)
        _ = stockService.createLog(
            type: "purchase",
            medicine: medicine,
            package: package,
            operationId: UUID()
        )
        let initialUnits = stockService.units(for: package)

        let useCase = RecordIntakeUseCase(
            eventStore: CoreDataEventStore(context: context),
            clock: FixedClock(date: Date())
        )
        let operationId = UUID()
        let request = RecordIntakeRequest(
            operationId: operationId,
            medicineId: MedicineId(medicine.id),
            therapyId: nil,
            packageId: PackageId(package.id)
        )

        _ = try useCase.execute(request)

        let actionService = MedicineActionService(context: context)
        XCTAssertTrue(actionService.undoLog(operationId: operationId))

        let intakeRequest: NSFetchRequest<Log> = Log.fetchRequest() as! NSFetchRequest<Log>
        intakeRequest.predicate = NSPredicate(format: "type == 'intake'")
        let intakeLogs = try context.fetch(intakeRequest)

        let undoRequest: NSFetchRequest<Log> = Log.fetchRequest() as! NSFetchRequest<Log>
        undoRequest.predicate = NSPredicate(format: "type == 'intake_undo'")
        let undoLogs = try context.fetch(undoRequest)

        XCTAssertEqual(intakeLogs.count, 1)
        XCTAssertEqual(undoLogs.count, 1)
        XCTAssertEqual(undoLogs.first?.reversal_of_operation_id, operationId)
        XCTAssertEqual(stockService.units(for: package), initialUnits)
        XCTAssertEqual(medicine.effectiveIntakeLogs().count, 0)
    }

    func testSaveFailureDoesNotLeavePartialState() throws {
        let model = try makeModel()
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil, options: nil)

        let context = FailingSaveContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        context.shouldFailSave = false

        let medicine = try makeMedicine(context: context)
        let package = try makePackage(context: context, medicine: medicine)
        try context.save()

        let stockService = StockService(context: context)
        _ = stockService.createLog(
            type: "purchase",
            medicine: medicine,
            package: package,
            operationId: UUID()
        )
        let initialUnits = stockService.units(for: package)

        context.shouldFailSave = true
        let operationId = UUID()
        let log = stockService.createLog(
            type: "intake",
            medicine: medicine,
            package: package,
            operationId: operationId
        )

        XCTAssertNil(log)
        XCTAssertEqual(stockService.units(for: package), initialUnits)
        XCTAssertEqual(try fetchLogs(context: context, operationId: operationId).count, 0)
    }

    func testConcurrentCallsWithSameOperationIdCreateSingleLog() throws {
        let container = try makeContainer()
        let viewContext = container.viewContext
        let medicine = try makeMedicine(context: viewContext)
        let package = try makePackage(context: viewContext, medicine: medicine)
        try viewContext.save()

        let stockService = StockService(context: viewContext)
        _ = stockService.createLog(
            type: "purchase",
            medicine: medicine,
            package: package,
            operationId: UUID()
        )

        let backgroundContext = container.newBackgroundContext()
        let useCase = RecordIntakeUseCase(
            eventStore: CoreDataEventStore(context: backgroundContext),
            clock: FixedClock(date: Date())
        )
        let operationId = UUID()
        let request = RecordIntakeRequest(
            operationId: operationId,
            medicineId: MedicineId(medicine.id),
            therapyId: nil,
            packageId: PackageId(package.id)
        )

        let group = DispatchGroup()
        let queue = DispatchQueue.global(qos: .userInitiated)
        for _ in 0..<2 {
            group.enter()
            queue.async {
                _ = try? useCase.execute(request)
                group.leave()
            }
        }
        group.wait()

        backgroundContext.performAndWait {
            let request: NSFetchRequest<Log> = Log.fetchRequest() as! NSFetchRequest<Log>
            request.predicate = NSPredicate(format: "operation_id == %@", operationId as CVarArg)
            let logs = (try? backgroundContext.fetch(request)) ?? []
            XCTAssertEqual(logs.count, 1)
        }
    }

    func testStockNeverNegative() throws {
        let container = try makeContainer()
        let context = container.viewContext
        let medicine = try makeMedicine(context: context)
        let package = try makePackage(context: context, medicine: medicine)
        try context.save()

        let stockService = StockService(context: context)
        let log = stockService.createLog(
            type: "intake",
            medicine: medicine,
            package: package,
            operationId: UUID()
        )

        XCTAssertNotNil(log)
        XCTAssertEqual(stockService.units(for: package), 0)
    }

    func testRecordPurchaseIdempotent() throws {
        let container = try makeContainer()
        let context = container.viewContext
        let medicine = try makeMedicine(context: context)
        let package = try makePackage(context: context, medicine: medicine)
        try context.save()

        let stockService = StockService(context: context)
        let initialUnits = stockService.units(for: package)

        let useCase = RecordPurchaseUseCase(
            eventStore: CoreDataEventStore(context: context),
            clock: FixedClock(date: Date())
        )
        let operationId = UUID()
        let request = RecordPurchaseRequest(
            operationId: operationId,
            medicineId: MedicineId(medicine.id),
            packageId: PackageId(package.id)
        )

        _ = try useCase.execute(request)
        _ = try useCase.execute(request)

        let logs = try fetchLogs(context: context, operationId: operationId)
        XCTAssertEqual(logs.count, 1)
        let packSize = max(1, Int(package.numero))
        XCTAssertEqual(stockService.units(for: package), initialUnits + packSize)
    }

    func testUndoPurchaseCreatesReversalAndRestoresStock() throws {
        let container = try makeContainer()
        let context = container.viewContext
        let medicine = try makeMedicine(context: context)
        let package = try makePackage(context: context, medicine: medicine)
        try context.save()

        let stockService = StockService(context: context)
        let initialUnits = stockService.units(for: package)

        let useCase = RecordPurchaseUseCase(
            eventStore: CoreDataEventStore(context: context),
            clock: FixedClock(date: Date())
        )
        let operationId = UUID()
        let request = RecordPurchaseRequest(
            operationId: operationId,
            medicineId: MedicineId(medicine.id),
            packageId: PackageId(package.id)
        )

        _ = try useCase.execute(request)

        let actionService = MedicineActionService(context: context)
        XCTAssertTrue(actionService.undoLog(operationId: operationId))

        let purchaseRequest: NSFetchRequest<Log> = Log.fetchRequest() as! NSFetchRequest<Log>
        purchaseRequest.predicate = NSPredicate(format: "type == 'purchase'")
        let purchaseLogs = try context.fetch(purchaseRequest)

        let undoRequest: NSFetchRequest<Log> = Log.fetchRequest() as! NSFetchRequest<Log>
        undoRequest.predicate = NSPredicate(format: "type == 'purchase_undo'")
        let undoLogs = try context.fetch(undoRequest)

        XCTAssertEqual(purchaseLogs.count, 1)
        XCTAssertEqual(undoLogs.count, 1)
        XCTAssertEqual(undoLogs.first?.reversal_of_operation_id, operationId)
        XCTAssertEqual(stockService.units(for: package), initialUnits)
        XCTAssertEqual(medicine.effectivePurchaseLogs().count, 0)
    }
}
