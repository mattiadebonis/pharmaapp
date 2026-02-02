import Foundation
import CoreData
@testable import PharmaApp

enum TestCoreDataFactory {
    static func makeModel() throws -> NSManagedObjectModel {
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
        throw NSError(domain: "TestCoreDataFactory", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing Medicine entity in PharmaApp model"])
    }

    static func makeContainer() throws -> NSPersistentContainer {
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
            throw NSError(domain: "TestCoreDataFactory", code: 3, userInfo: [NSLocalizedDescriptionKey: "Required entities missing from context model"])
        }
        let context = container.viewContext
        let requiredEntityNames = ["Medicine", "Package", "Log", "Stock"]
        for name in requiredEntityNames {
            if NSEntityDescription.entity(forEntityName: name, in: context) == nil {
                throw NSError(domain: "TestCoreDataFactory", code: 6, userInfo: [NSLocalizedDescriptionKey: "Entity \(name) not resolved in context"])
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        return container
    }

    static func makeMedicine(context: NSManagedObjectContext, id: UUID = UUID()) throws -> Medicine {
        guard let entity = NSEntityDescription.entity(forEntityName: "Medicine", in: context) else {
            throw NSError(domain: "TestCoreDataFactory", code: 4, userInfo: [NSLocalizedDescriptionKey: "Medicine entity not found"])
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

    static func makePackage(
        context: NSManagedObjectContext,
        id: UUID = UUID(),
        medicine: Medicine,
        numero: Int32 = 10
    ) throws -> Package {
        guard let entity = NSEntityDescription.entity(forEntityName: "Package", in: context) else {
            throw NSError(domain: "TestCoreDataFactory", code: 5, userInfo: [NSLocalizedDescriptionKey: "Package entity not found"])
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

    static func fetchLogs(context: NSManagedObjectContext, operationId: UUID) throws -> [Log] {
        let request: NSFetchRequest<Log> = Log.fetchRequest() as! NSFetchRequest<Log>
        request.predicate = NSPredicate(format: "operation_id == %@", operationId as CVarArg)
        return try context.fetch(request)
    }
}
