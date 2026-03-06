import Foundation
import CoreData

final class CoreDataMedicinePackageRepository: MedicinePackageRepository {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func fetchAll() throws -> [MedicinePackageSnapshot] {
        let request = MedicinePackage.extractEntries()
        let entries = try context.fetch(request)
        return entries.map { makeSnapshot(from: $0) }
    }

    func fetchEntries(cabinetId: UUID) throws -> [MedicinePackageSnapshot] {
        let request: NSFetchRequest<MedicinePackage> = MedicinePackage.fetchRequest() as! NSFetchRequest<MedicinePackage>
        request.predicate = NSPredicate(format: "cabinet.id == %@", cabinetId as CVarArg)
        let entries = try context.fetch(request)
        return entries.map { makeSnapshot(from: $0) }
    }

    private func makeSnapshot(from entry: MedicinePackage) -> MedicinePackageSnapshot {
        let therapyIds: [TherapyId] = {
            let linked = (entry.therapies ?? []).filter {
                $0.medicine.objectID == entry.medicine.objectID
                    && $0.package.objectID == entry.package.objectID
            }
            let fallback = (entry.medicine.therapies ?? []).filter {
                $0.package.objectID == entry.package.objectID
            }
            let merged = Set(linked).union(fallback)
            return merged.map { TherapyId($0.id) }
        }()

        return MedicinePackageSnapshot(
            id: entry.id,
            externalKey: entry.objectID.uriRepresentation().absoluteString,
            medicineId: MedicineId(entry.medicine.id),
            packageId: PackageId(entry.package.id),
            cabinetId: entry.cabinet?.id,
            medicineName: entry.medicine.nome,
            principioAttivo: entry.medicine.principio_attivo,
            packageDescription: entry.package.denominazione_package ?? "",
            therapyIds: therapyIds
        )
    }
}
