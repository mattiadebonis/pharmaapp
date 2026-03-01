import Foundation
import CoreData

final class CoreDataMedicineRepository: MedicineRepository {
    private let context: NSManagedObjectContext
    private let snapshotBuilder: CoreDataSnapshotBuilder

    init(context: NSManagedObjectContext) {
        self.context = context
        self.snapshotBuilder = CoreDataSnapshotBuilder(context: context)
    }

    func fetchAllInCabinet() throws -> [MedicineSnapshot] {
        let request: NSFetchRequest<Medicine> = Medicine.fetchRequest() as! NSFetchRequest<Medicine>
        request.predicate = NSPredicate(format: "in_cabinet == YES")
        request.sortDescriptors = [NSSortDescriptor(key: "nome", ascending: true)]
        let medicines = try context.fetch(request)
        return medicines.map { snapshotBuilder.makeMedicineSnapshot(medicine: $0, logs: Array($0.logs ?? [])) }
    }

    func fetchMedicine(id: MedicineId) throws -> MedicineSnapshot? {
        let request: NSFetchRequest<Medicine> = Medicine.fetchRequest() as! NSFetchRequest<Medicine>
        request.predicate = NSPredicate(format: "id == %@", id.rawValue as CVarArg)
        request.fetchLimit = 1
        guard let medicine = try context.fetch(request).first else { return nil }
        return snapshotBuilder.makeMedicineSnapshot(medicine: medicine, logs: Array(medicine.logs ?? []))
    }

    func fetchMedicineSnapshots(ids: [MedicineId]) throws -> [MedicineSnapshot] {
        let uuids = ids.map { $0.rawValue }
        let request: NSFetchRequest<Medicine> = Medicine.fetchRequest() as! NSFetchRequest<Medicine>
        request.predicate = NSPredicate(format: "id IN %@", uuids)
        let medicines = try context.fetch(request)
        return medicines.map { snapshotBuilder.makeMedicineSnapshot(medicine: $0, logs: Array($0.logs ?? [])) }
    }
}
