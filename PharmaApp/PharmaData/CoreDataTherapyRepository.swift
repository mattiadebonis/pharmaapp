import Foundation
import CoreData

final class CoreDataTherapyRepository: TherapyRepository {
    private let context: NSManagedObjectContext
    private let snapshotBuilder: CoreDataSnapshotBuilder

    init(context: NSManagedObjectContext) {
        self.context = context
        self.snapshotBuilder = CoreDataSnapshotBuilder(context: context)
    }

    func fetchTherapies(for medicineId: MedicineId) throws -> [TherapySnapshot] {
        let request: NSFetchRequest<Therapy> = Therapy.fetchRequest() as! NSFetchRequest<Therapy>
        request.predicate = NSPredicate(format: "medicine.id == %@", medicineId.rawValue as CVarArg)
        let therapies = try context.fetch(request)
        return therapies.map { snapshotBuilder.makeTherapySnapshot(therapy: $0) }
    }

    func fetchTherapy(id: TherapyId) throws -> TherapySnapshot? {
        let request: NSFetchRequest<Therapy> = Therapy.fetchRequest() as! NSFetchRequest<Therapy>
        request.predicate = NSPredicate(format: "id == %@", id.rawValue as CVarArg)
        request.fetchLimit = 1
        guard let therapy = try context.fetch(request).first else { return nil }
        return snapshotBuilder.makeTherapySnapshot(therapy: therapy)
    }
}
